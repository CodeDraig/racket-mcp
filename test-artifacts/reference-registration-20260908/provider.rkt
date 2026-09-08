#lang racket/base
(require syntax-spec-v3 (for-syntax racket/base))
(provide value)
(syntax-spec
 (binding-class item #:reference-compiler immutable-reference-compiler)
 (host-interface/definition (define-item name:item expression:racket-expr)
  #:binding (export name)
  #:lhs [#'name]
  #:rhs [#'expression]))
(define-item value 7)
