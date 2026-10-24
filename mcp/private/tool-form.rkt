#lang racket/base
(require "../descriptor.rkt"
         "../json.rkt"
         "domain-bindings.rkt"
         "handler.rkt"
         "registration.rkt"
         (for-syntax racket/base syntax/parse "declaration-syntax.rkt"))
(provide tool)
(define-syntax (tool stx)
  (syntax-parse stx
    [(_ (name:id a:arg ...) (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:output output:expr) #:defaults ([output #'missing]))
        (~optional (~seq #:annotations annotations:expr) #:defaults ([annotations #'(hasheq)]))
        (~optional (~seq #:changes [outcome:id changes:expr]) #:defaults ([outcome #'committed] [changes #''()]))
        body:expr ...+)
     (define ids (syntax->list #'(a.id ...)))
     (check-binders (append ids (list #'outcome)) stx)
     (check-literal-schema! #'output)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     #`(begin (define-operation-value name
         (make-tool (symbol->string 'name) (list #,@args)
                    (mcp-bound-handler name (a.id ...) body ...)
                    #:description description #:output (checked-schema-expression output) #:annotations annotations
                    #:changes (lambda (bound outcome)
                                (let (#,@(for/list ([id ids]) #`[#,id (hash-ref bound '#,id)])) changes)))) (register-declaration name #:declaration tool name #,stx))]))
