#lang racket/base
(require rackunit mcp/schema)

;; Native schemas and decoded JSON can represent the same number differently.
(for ([pair (in-list (list (cons 1 1.0) (cons 1/2 0.5) (cons 0 -0.0)
                           (cons '(1 (2)) '(1.0 (2.0)))
                           (cons (hasheq 'a '(1 2) 'b #f)
                                 (hash 'b #f 'a '(1.0 2.0)))))])
  (define exact-value (car pair))
  (define inexact-value (cdr pair))
  (check-true (valid? (hasheq 'const exact-value) inexact-value))
  (check-true (valid? (hasheq 'const inexact-value) exact-value))
  (check-true (valid? (hasheq 'enum (list inexact-value)) exact-value))
  (check-false (valid? (hasheq 'uniqueItems #t) (list exact-value inexact-value))))

;; Numeric equality must not erase JSON types, array order, or object members.
(for ([pair (in-list (list (cons #f 0) (cons "1" 1) (cons 1 2.0)
                           (cons '(1 2) '(2.0 1.0))
                           (cons (hasheq 'a 1) (hasheq 'b 1.0))
                           (cons (hasheq 'a 1) (hasheq 'a 1.0 'b 2))))])
  (check-false (valid? (hasheq 'const (car pair)) (cdr pair)))
  (check-false (valid? (hasheq 'enum (list (car pair))) (cdr pair)))
  (check-true (valid? (hasheq 'uniqueItems #t) (list (car pair) (cdr pair)))))

;; Preserve the existing hash-based cost of checking a large distinct array.
(check-true (valid? (hasheq 'uniqueItems #t) (for/list ([n (in-range 2000)]) n)))
