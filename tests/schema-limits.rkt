#lang racket/base
(require rackunit mcp/schema)
(check-exn #rx"work limit" (lambda () (validate #t 1 #:max-steps 1)))
(check-exn exn:fail? (lambda () (valid? #t 1 #:max-steps 0)))
;; A compact, shallow schema expands to many applicator visits through references.
(define definitions
  (for/fold ([defs (hasheq 'n0 #t)]) ([i (in-range 1 17)])
    (define reference (hasheq '$ref (format "#/$defs/n~a" (sub1 i))))
    (hash-set defs (string->symbol (format "n~a" i)) (hasheq 'allOf (list reference reference)))))
(define branching (hasheq '$defs definitions '$ref "#/$defs/n16"))
(check-exn #rx"work limit" (lambda () (validate branching 1 #:max-steps 50000)))
(check-equal? (validate branching 1 #:max-steps 1000000) '())
;; A failed validation does not exhaust the next independent call's allowance.
(check-true (valid? (hasheq 'type "integer") 1))
(define cyclic (make-hasheq))
(hash-set! cyclic '$defs (hasheq 'again cyclic))
(check-exn #rx"cyclic schema registry" (lambda () (validate #t 1 #:registry (hash "https://example.test/cycle" cyclic))))
