#lang racket/base
(require racket/list racket/string)
(provide elicitation-format-valid?)

;; MCP's four string formats are assertions only at the elicitation boundary.
;; RFC 3339 section 5.6/5.7, RFC 3986 appendix A, RFC 5321 section 4.1.2.
;; These checks perform no DNS, network, locale or machine-time-zone operations.
(define (leap-year? year)
  (and (zero? (modulo year 4))
       (or (not (zero? (modulo year 100))) (zero? (modulo year 400)))))
(define (month-days year month)
  (if (and (= month 2) (leap-year? year)) 29
      (vector-ref '#(0 31 28 31 30 31 30 31 31 30 31 30 31) month)))
(define (date-parts value)
  (define found (regexp-match #px"^([0-9]{4})-([0-9]{2})-([0-9]{2})$" value))
  (and found
       (let* ([parts (map string->number (cdr found))]
              [year (car parts)] [month (cadr parts)] [day (caddr parts)])
         (and (<= 1 month 12) (<= 1 day (month-days year month)) parts))))
(define (timestamp? value)
  (define found
    (regexp-match #px"^([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.][0-9]+)?([Zz]|([+-])([0-9]{2}):([0-9]{2}))$" value))
  (and found
       (let ([date (date-parts (list-ref found 1))]
             [hour (string->number (list-ref found 2))]
             [minute (string->number (list-ref found 3))]
             [second (string->number (list-ref found 4))]
             [offset-hour (if (list-ref found 7) (string->number (list-ref found 7)) 0)]
             [offset-minute (if (list-ref found 8) (string->number (list-ref found 8)) 0)])
         (and date (< hour 24) (< minute 60) (<= second 60)
              (< offset-hour 24) (< offset-minute 60)
              (or (< second 60)
                  ;; Leap seconds occur at a UTC month-end, regardless of the
                  ;; written offset. This checks the possible position, not an
                  ;; external historical/predicted leap-second bulletin.
                  (let* ([offset (* (if (equal? (list-ref found 6) "-") -1 1)
                                    (+ (* 60 offset-hour) offset-minute))]
                         [utc-minute (- (+ (* 60 hour) minute) offset)]
                         [utc-day (+ (caddr date) (floor (/ utc-minute 1440)))])
                    (and (= (modulo utc-minute 1440) 1439)
                         (or (= utc-day 0)
                             (= utc-day (month-days (car date) (cadr date)))))))))))

(define (ipv4? value [leading-zero? #f])
  (define parts (string-split value "." #:trim? #f))
  (and (= (length parts) 4)
       (for/and ([part (in-list parts)])
         (and (regexp-match? #px"^[0-9]{1,3}$" part)
              (or leading-zero? (= (string-length part) 1) (not (char=? (string-ref part 0) #\0)))
              (<= (string->number part) 255)))))
(define (ipv6? value [leading-zero? #f])
  (define halves (string-split value "::" #:trim? #f))
  (and (<= (length halves) 2)
       (let* ([compressed? (= (length halves) 2)]
              [parts (append-map (lambda (half) (if (equal? half "") '() (string-split half ":" #:trim? #f))) halves)]
              [part-count (length parts)]
              [widths (for/list ([part (in-list parts)] [i (in-naturals)])
                        (cond [(regexp-match? #px"^[0-9A-Fa-f]{1,4}$" part) 1]
                              [(and (= i (sub1 part-count))
                                    (not (string-suffix? value "::"))
                                    (ipv4? part leading-zero?)) 2]
                              [else #f]))])
         (and (andmap values widths)
              (if compressed? (< (apply + widths) 8) (= (apply + widths) 8))))))

(define unreserved "A-Za-z0-9._~-")
(define sub-delims "!$&'()*+,;=")
(define (component-pattern extra)
  (pregexp (string-append "^(?:[" extra sub-delims unreserved "]|%[A-Fa-f0-9]{2})*$")))
(define reg-name-pattern (component-pattern ""))
(define userinfo-pattern (component-pattern ":"))
(define path-pattern (component-pattern ":@/"))
(define query-pattern (component-pattern ":@/?"))
(define future-pattern (pregexp (string-append "^[vV][A-Fa-f0-9]+[.][" ":" sub-delims unreserved "]+$")))
(define (split-authority value delimiter)
  (if (equal? value "") '("") (string-split value delimiter #:trim? #f)))
(define (authority? value)
  (define user-host (split-authority value "@"))
  (and (<= (length user-host) 2)
       (or (= (length user-host) 1) (regexp-match? userinfo-pattern (car user-host)))
       (let ([host-port (last user-host)])
         (cond [(string-prefix? host-port "[")
                (define found (regexp-match #px"^\\[([^]]+)\\](?::[0-9]*)?$" host-port))
                (and found (or (ipv6? (cadr found)) (regexp-match? future-pattern (cadr found))))]
               [else
                (define parts (split-authority host-port ":"))
                (and (<= (length parts) 2)
                     (regexp-match? reg-name-pattern (car parts))
                     (or (= (length parts) 1) (regexp-match? #px"^[0-9]*$" (cadr parts))))]))))
(define (uri? value)
  (define found (regexp-match #px"^[A-Za-z][A-Za-z0-9+.-]*:([^?#]*)(?:[?]([^#]*))?(?:#(.*))?$" value))
  (and found
       (let ([hierarchy (cadr found)])
         (and (or (not (caddr found)) (regexp-match? query-pattern (caddr found)))
              (or (not (cadddr found)) (regexp-match? query-pattern (cadddr found)))
              (if (string-prefix? hierarchy "//")
                  (let* ([parts (regexp-match #px"^//([^/]*)(/.*)?$" hierarchy)]
                         [authority (cadr parts)] [path (or (caddr parts) "")])
                    (and (authority? authority) (regexp-match? path-pattern path)))
                  (regexp-match? path-pattern hierarchy))))))

(define atom-pattern #px"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:[.][A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*$")
(define (quoted-local? value)
  (define size (string-length value))
  (and (>= size 2) (char=? (string-ref value 0) #\")
       (char=? (string-ref value (sub1 size)) #\")
       (let loop ([i 1])
         (cond [(= i (sub1 size)) #t]
               [else
                (define c (string-ref value i))
                (cond [(char=? c #\\)
                       (and (< (add1 i) (sub1 size))
                            (<= 32 (char->integer (string-ref value (add1 i))) 126)
                            (loop (+ i 2)))]
                      [else (and (<= 32 (char->integer c) 126)
                                 (not (char=? c #\")) (loop (add1 i)))])]))))
(define domain-pattern #px"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:[.][A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*$")
(define (email? value)
  ;; The final @ is the separator; quoted local parts may contain earlier @s.
  (define found (regexp-match #px"^(.*)@([^@]*)$" value))
  (and found
       (or (regexp-match? atom-pattern (cadr found)) (quoted-local? (cadr found)))
       (let ([domain (caddr found)])
         (or (regexp-match? domain-pattern domain)
             (let ([literal (regexp-match #px"^\\[([^]]+)\\]$" domain)])
               (and literal
                    (let ([address (cadr literal)])
                      (if (string-prefix? (string-downcase address) "ipv6:")
                          (ipv6? (substring address 5) #t)
                          (ipv4? address #t)))))))))
(define (elicitation-format-valid? name value)
  (or (not (string? value))
       (case (string->symbol name)
         [(date) (and (date-parts value) #t)]
         [(date-time) (timestamp? value)]
         [(email) (email? value)]
         [(uri) (uri? value)]
         [else #f])))
