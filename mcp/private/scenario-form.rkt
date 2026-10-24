#lang racket/base
(require "../scenario-process.rkt" "../scenario-session.rkt" "../clock.rkt" "registration.rkt"
         (for-syntax racket/base syntax/parse))
(provide scenario)
(define-syntax (scenario stx)
  (syntax-parse stx
    [(_ (name:id process:id) #:command command:expr
        (~optional (~seq #:transport transport:expr) #:defaults ([transport #''stdio]))
        (~optional (~seq #:capabilities capabilities:expr) #:defaults ([capabilities #'(hasheq)]))
        (~optional (~seq #:timeout timeout:expr) #:defaults ([timeout #'5]))
        (~optional (~seq #:shutdown-timeout shutdown:expr) #:defaults ([shutdown #'2]))
        (~optional (~seq #:stderr-limit limit:expr) #:defaults ([limit #'65536]))
        (~optional (~seq #:directory directory:expr) #:defaults ([directory #'(current-directory)]))
        (~optional (~seq #:environment environment:expr) #:defaults ([environment #'(current-environment-variables)]))
        body:expr ...+)
     #`(begin
        (register-declaration #f #:scenario name #,stx)
        (module+ test
         (require rackunit)
         (test-case (symbol->string 'name)
           (call-with-scenario-process command
             (lambda (process) body ...)
             #:transport transport #:capabilities capabilities #:timeout timeout
             #:shutdown-timeout shutdown #:stderr-limit limit #:directory directory #:environment environment))))]
    [(_ (name:id session:id) #:interface interface:expr
        (~optional (~seq #:transport transport:expr) #:defaults ([transport #''local]))
        (~optional (~seq #:clock clock:expr) #:defaults ([clock #'(make-manual-clock)]))
        (~optional (~seq #:principal principal:expr) #:defaults ([principal #'"scenario"]))
        (~optional (~seq #:adapters adapters:expr) #:defaults ([adapters #'(hasheq)]))
        (~optional (~seq #:capabilities capabilities:expr) #:defaults ([capabilities #'(hasheq)]))
        (~optional (~seq #:state state:expr) #:defaults ([state #'#f]))
        (~optional (~seq #:authorize authorize:expr) #:defaults ([authorize #'(lambda (_p _m _a) #t)]))
        (~optional (~seq #:timeout timeout:expr) #:defaults ([timeout #'5]))
        (~optional (~seq #:sse? sse:expr) #:defaults ([sse #'#f]))
        body:expr ...+)
     #`(begin
        (register-declaration #f #:scenario name #,stx)
        (module+ test
         (require rackunit)
         (test-case (symbol->string 'name)
           (call-with-scenario-session interface
             (lambda (session) body ...)
             #:transport transport #:clock clock #:principal principal #:adapters adapters
             #:capabilities capabilities #:state state #:authorize authorize #:timeout timeout #:sse? sse))))]
    [(_ name:id body ...+)
     #`(begin
         (register-declaration #f #:scenario name #,stx)
         (module+ test (require rackunit) (test-case (symbol->string 'name) body ...)))]))
