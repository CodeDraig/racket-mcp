#lang racket/base
(require racket/list racket/string)
(provide ipv4? ipv6?)
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

