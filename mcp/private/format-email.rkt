#lang racket/base
(require racket/string "format-ip.rkt")
(provide email?)
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
