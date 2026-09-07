#lang racket/base
(require (for-template racket/base))
(provide (struct-out resource-binding))
(struct resource-binding (target arity)
  #:property prop:procedure
  (lambda (self stx)
    (syntax-case stx ()
      [id (identifier? #'id) (resource-binding-target self)]
      [(_ argument ...)
       (begin
         (unless (= (length (syntax->list #'(argument ...))) (resource-binding-arity self))
           (raise-syntax-error #f (format "resource reference expects ~a arguments" (resource-binding-arity self)) stx))
         #`(#,(resource-binding-target self) argument ...))])))
