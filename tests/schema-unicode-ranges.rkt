#lang racket/base
(require rackunit "../mcp/private/pattern.rkt")

;; Independent definition: ECMAScript whitespace is Zs plus these control/line
;; characters. Check both complements across every representable Unicode scalar.
(define whitespace (schema-pattern "^\\s$"))
(define non-whitespace (schema-pattern "^\\S$"))
(check-false
 (for/first ([n (in-range #x110000)] #:unless (<= #xd800 n #xdfff)
             #:when
             (let* ([c (integer->char n)] [value (string c)]
                    [expected (or (eq? (char-general-category c) 'zs)
                                  (and (memv n '(9 10 11 12 13 8232 8233 65279)) #t))])
               (not (and (equal? (regexp-match? whitespace value) expected)
                         (equal? (regexp-match? non-whitespace value) (not expected))))))
   n)
 "Whitespace/complement mismatch among 1,112,064 Unicode scalar values")

;; Exercise UTF-8 width and suffix boundaries, including the native FF40 hole.
(for ([range '((#x7e #x81) (#x7fe #x801) (#xff00 #xffff) (#xfffe #x10001)
               (#x1f400 #x1f47f) (#x10ff80 #x10ffff) (#x3b1 #x3c9))])
  (define lower (car range))
  (define upper (cadr range))
  (define pattern (schema-pattern (string-append "^[" (string (integer->char lower)) "-"
                                               (string (integer->char upper)) "]$")))
  (check-false
   (for/first ([n (in-range (max 0 (- lower 2)) (min #x110000 (+ upper 3)))]
               #:when (not (equal? (regexp-match? pattern (string (integer->char n))) (<= lower n upper))))
     n)
   (format "Unicode interval ~s" range)))
