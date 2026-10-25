#lang racket/base
(provide json-value-key json-value=? exact-json-number)
(define (exact-json-number v) (if (exact? v) v (inexact->exact v)))
;; No wire roundtrip: keep represented numeric values, object membership, and
;; array order without imposing the decoder's unrelated input limits.
(define (json-value-key value [visit void])
  (visit)
  (cond [(rational? value) (exact-json-number value)]
        [(hash? value) (for/hasheq ([(key child) (in-hash value)])
                         (values key (json-value-key child visit)))]
        [(list? value) (map (lambda (child) (json-value-key child visit)) value)]
        [else value]))
(define (json-value=? a b [visit void])
  (equal? (json-value-key a visit) (json-value-key b visit)))
