#lang racket/base
(require rackunit racket/runtime-path mcp/cli
         (prefix-in library: "../examples/library.rkt"))
(define-runtime-path side-effect "manifest-side-effect.rkt")
(define-runtime-path library "../examples/library.rkt")
(check-equal? (length (read-manifest side-effect)) 1)
(check-equal? (length (read-manifest library)) 4)
(check-equal? (map (lambda (d) (hash-ref d 'name)) (read-manifest library)) '("library" books search-books books))
(check-equal? (map (lambda (d) (hash-ref d 'kind)) (read-manifest library)) '(server resource tool completion))
(check-true (andmap (lambda (d) (exact-positive-integer? (hash-ref d 'line))) (read-manifest library)))
