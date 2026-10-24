#lang racket/base

(provide json-null missing missing? json-value?)
(define json-null 'null)
(struct absent () #:transparent)
(define missing (absent))
(define missing? absent?)
(define (json-value? v)
  (or (eq? v json-null) (boolean? v) (string? v)
      (and (rational? v) (real? v))
      (and (list? v) (andmap json-value? v))
      (and (hash? v) (for/and ([(k x) (in-hash v)])
                       (and (symbol? k) (json-value? x))))))

