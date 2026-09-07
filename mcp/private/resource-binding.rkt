#lang racket/base
(require (for-template racket/base))
(provide (struct-out resource-binding) lookup-resource-binding)
(struct resource-binding (target arity name arguments)
  #:property prop:procedure
  (lambda (self stx)
    (syntax-case stx ()
      [id (identifier? #'id) (resource-binding-target self)]
      [(_ argument ...)
       (begin
         (unless (= (length (syntax->list #'(argument ...))) (resource-binding-arity self))
           (raise-syntax-error #f (format "resource reference expects ~a arguments" (resource-binding-arity self)) stx))
         #`(#,(resource-binding-target self) argument ...))])))

;; Quoted host syntax can refer to an unavailable namespace during expansion.
;; Such a binding supplies no declaration metadata; local declarations are also
;; checked by the module finalizer after their bindings have been established.
(define (lookup-resource-binding id)
  (with-handlers ([exn:fail:syntax? (lambda (_) #f)])
    (define value (syntax-local-value id (lambda () #f)))
    (and (resource-binding? value) value)))
