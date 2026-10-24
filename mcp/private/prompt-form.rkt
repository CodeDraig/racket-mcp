#lang racket/base
(require "../descriptor.rkt"
         "domain-bindings.rkt"
         "handler.rkt"
         "registration.rkt"
         "workflow-compiler.rkt"
         (for-syntax racket/base syntax/parse "declaration-syntax.rkt" "prompt-binding.rkt"))
(provide prompt)
(define-syntax (prompt stx)
  (syntax-parse stx
    [(_ (name:id a:prompt-arg ...) (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        #:workflow version:str body ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default) (attribute a.codec)))
     (define-values (program summaries)
       (compile-workflow #'(workflow-program (name [a.id a.spec] ...) #:version version body ...) #t #:summaries? #t))
     (define hidden (car (generate-temporaries #'(name))))
     #`(begin
         (define-operation-value #,hidden (make-prompt (symbol->string 'name) (list #,@args) #f #:description description
                                   #:workflow #,program))
         (define-syntax name (prompt-binding (quote-syntax #,hidden) 'name '(a.id ...)))
         (register-declaration name #:declaration prompt name #,stx #:workflow-nodes (#,@summaries)))]
    [(_ (name:id a:prompt-arg ...) (~optional (~seq #:description description:expr) #:defaults ([description #'""])) body:expr ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default) (attribute a.codec)))
     (define hidden (car (generate-temporaries #'(name))))
     #`(begin (define-operation-value #,hidden (make-prompt (symbol->string 'name) (list #,@args)
                                (mcp-bound-handler name (a.id ...) body ...)
                                #:description description)) (define-syntax name (prompt-binding (quote-syntax #,hidden) 'name '(a.id ...)))
         (register-declaration name #:declaration prompt name #,stx))]))

