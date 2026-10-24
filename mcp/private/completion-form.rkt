#lang racket/base
(require "../completion.rkt"
         "registration.rkt"
         (for-syntax racket/base syntax/parse "resource-binding.rkt" "prompt-binding.rkt"))
(provide completion)
(define-syntax (completion stx)
  (syntax-parse stx
    [(_ (target:id argument:id) handler:expr)
     (define binding (or (lookup-resource-binding #'target) (lookup-prompt-binding #'target)))
     (when (and binding
                (not (memq (syntax-e #'argument)
                           (if (resource-binding? binding) (resource-binding-arguments binding) (prompt-binding-arguments binding)))))
       (raise-syntax-error 'completion "unknown target argument" stx #'argument))
     #`(begin
         (register-declaration #f #:declaration completion target #,stx)
         (let ([descriptor (completion-descriptor target 'argument handler)])
           (register-declaration descriptor)
           descriptor))]))
