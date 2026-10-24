#lang racket/base
(require "../schema.rkt"
         "domain-bindings.rkt"
         "registration.rkt"
         (for-syntax racket/base syntax/parse "declaration-syntax.rkt"))
(provide schema)
(define-syntax (schema stx)
  (syntax-parse stx
    [(_ name:id value:expr)
     (check-literal-schema! #'value)
     #`(begin (define-schema-value name (check-schema! (checked-schema-expression value)))
              (register-declaration #f #:declaration schema name #,stx))]))
