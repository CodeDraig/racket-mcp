#lang racket/base
(require racket/string racket/list)
(provide (struct-out authentication-challenge) parse-authenticate)
(struct authentication-challenge (scheme parameters token68) #:transparent)
(define token-pattern "[!#$%&'*+.^_`|~0-9A-Za-z-]+")
(define parameter-start (pregexp (string-append "^(" token-pattern ")[\t ]*=[\t ]*(.*)$")))
(define scheme-start (pregexp (string-append "^(" token-pattern ")(?: +(.*))?$")))
(define token-value (pregexp (string-append "^" token-pattern "$")))
(define (segments value)
  (define parts '())
  (define start 0)
  (define quoted? #f)
  (define escaped? #f)
  (for ([c (in-string value)] [i (in-naturals)])
    (define n (char->integer c))
    (unless (or (= n 9) (and (>= n 32) (not (= n 127))))
      (error 'parse-authenticate "control character in authentication header"))
    (cond [escaped? (set! escaped? #f)]
          [(and quoted? (char=? c #\\)) (set! escaped? #t)]
          [(char=? c #\") (set! quoted? (not quoted?))]
          [(and (not quoted?) (char=? c #\,))
           (set! parts (cons (substring value start i) parts)) (set! start (add1 i))]))
  (when (or quoted? escaped?) (error 'parse-authenticate "unterminated quoted value"))
  (filter (lambda (s) (not (string=? s "")))
          (map string-trim (reverse (cons (substring value start) parts)))))
(define (parameter-value value)
  (cond [(regexp-match? token-value value) (string->immutable-string value)]
        [(and (>= (string-length value) 2) (string-prefix? value "\"") (string-suffix? value "\""))
         (define out (open-output-string))
         (define escaped? #f)
         (for ([c (in-string value 1 (sub1 (string-length value)))])
           (cond [escaped? (write-char c out) (set! escaped? #f)]
                 [(char=? c #\\) (set! escaped? #t)]
                 [(char=? c #\") (error 'parse-authenticate "unescaped quote in parameter")]
                 [else (write-char c out)]))
         (when escaped? (error 'parse-authenticate "dangling quoted escape"))
         (string->immutable-string (get-output-string out))]
        [else (error 'parse-authenticate "invalid authentication parameter value")]))
(define (parse-authenticate fields #:max-bytes [limit 65536])
  (unless (exact-positive-integer? limit) (raise-argument-error 'parse-authenticate "exact-positive-integer?" limit))
  (unless (and (list? fields) (andmap string? fields)) (raise-argument-error 'parse-authenticate "list of header value strings" fields))
  (when (> (+ (max 0 (sub1 (length fields))) (for/sum ([s (in-list fields)]) (bytes-length (string->bytes/utf-8 s)))) limit)
    (error 'parse-authenticate "authentication header byte limit exceeded"))
  (define result '())
  (for ([field (in-list (list (string-join fields ",")))])
    (define current #f)
    (define (finish!) (when current (set! result (cons current result))))
    (define (add-parameter! match)
      (unless (and current (not (authentication-challenge-token68 current)))
        (error 'parse-authenticate "parameter without a parameterized challenge"))
      (define name (string-downcase (cadr match)))
      (define parameters (authentication-challenge-parameters current))
      (when (hash-has-key? parameters name) (error 'parse-authenticate "duplicate authentication parameter"))
      (when (>= (hash-count parameters) 64) (error 'parse-authenticate "too many authentication parameters"))
      (set! current (struct-copy authentication-challenge current
                     [parameters (hash-set parameters name (parameter-value (caddr match)))])))
    (for ([part (in-list (segments field))])
      (define param (regexp-match parameter-start part))
      (cond [param (add-parameter! param)]
            [else
             (finish!)
             (define scheme (regexp-match scheme-start part))
             (unless scheme (error 'parse-authenticate "invalid authentication challenge"))
             (set! current (authentication-challenge (string-downcase (cadr scheme)) (hash) #f))
             (define payload (caddr scheme))
             (when payload
               (define parameter (regexp-match parameter-start payload))
               (cond [(regexp-match? #px"^[A-Za-z0-9._~+/-]+=*$" payload)
                      (set! current (struct-copy authentication-challenge current [token68 payload]))]
                     [parameter (add-parameter! parameter)]
                     [else (error 'parse-authenticate "invalid challenge credentials")]))]))
    (finish!))
  (reverse result))
