#lang racket/base
(require "../descriptor.rkt"
         "domain-bindings.rkt"
         "handler.rkt"
         "registration.rkt"
         "workflow-compiler.rkt"
         (for-syntax racket/base syntax/parse "declaration-syntax.rkt" "resource-binding.rkt"))
(provide resource)
(define-syntax (resource stx)
  (syntax-parse stx
    [(_ (name:id a:arg ...) #:uri uri:expr
        (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:mime-type mime:expr) #:defaults ([mime #'#f]))
        (~optional (~seq #:render renderer:expr) #:defaults ([renderer #'#f]))
        (~optional (~seq #:matcher matcher:expr) #:defaults ([matcher #'#f]))
        (~optional (~seq #:depends-on dependencies:expr) #:defaults ([dependencies #''()]))
        (~optional (~seq #:ttl-ms ttl:expr) #:defaults ([ttl #'0]))
        #:workflow version:str body ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (check-literal-uri! #'uri ids)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     (define hidden
       (syntax-property (car (generate-temporaries #'(name))) 'mcp-resource-origin
                        (hasheq 'name (syntax-e #'name) 'source (format "~a" (syntax-source #'name))
                                'line (syntax-line #'name) 'column (syntax-column #'name)
                                'position (syntax-position #'name) 'span (syntax-span #'name))))
     (define-values (program summaries)
       (compile-workflow #'(workflow-program (name a ...) #:version version body ...) #t #:summaries? #t))
     #`(begin
         (define-resource-value #,hidden (make-resource (symbol->string 'name) uri #f #:description description #:mime-type mime #:render renderer
                                        #:arguments (list #,@args) #:matcher matcher #:ttl-ms ttl
                                        #:depends-on (lambda (bound) (let (#,@(for/list ([id ids]) #`[#,id (hash-ref bound '#,id)])) dependencies))
                                        #:workflow #,program))
         (define-syntax name (resource-binding (quote-syntax #,hidden) #,(length ids) 'name '(a.id ...)))
         (register-declaration name #:declaration resource name #,stx #:workflow-nodes (#,@summaries)))]
    [(_ (name:id a:arg ...) #:uri uri:expr
        (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:mime-type mime:expr) #:defaults ([mime #'#f]))
        (~optional (~seq #:render renderer:expr) #:defaults ([renderer #'#f]))
        (~optional (~seq #:matcher matcher:expr) #:defaults ([matcher #'#f]))
        (~optional (~seq #:depends-on dependencies:expr) #:defaults ([dependencies #''()]))
        (~optional (~seq #:ttl-ms ttl:expr) #:defaults ([ttl #'0])) body:expr ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (check-literal-uri! #'uri ids)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     (define hidden
       (syntax-property (car (generate-temporaries #'(name))) 'mcp-resource-origin
                        (hasheq 'name (syntax-e #'name) 'source (format "~a" (syntax-source #'name))
                                'line (syntax-line #'name) 'column (syntax-column #'name)
                                'position (syntax-position #'name) 'span (syntax-span #'name))))
     #`(begin (define-resource-value #,hidden (make-resource (symbol->string 'name) uri (mcp-owned-handler name (a.id ...) body ...) #:description description #:mime-type mime #:render renderer #:arguments (list #,@args) #:matcher matcher #:ttl-ms ttl
                                        #:depends-on (lambda (bound) (let (#,@(for/list ([id ids]) #`[#,id (hash-ref bound '#,id)])) dependencies))))
              (define-syntax name (resource-binding (quote-syntax #,hidden) #,(length ids) 'name '(a.id ...)))
              (register-declaration name #:declaration resource name #,stx))]))

