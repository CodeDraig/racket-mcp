#lang racket/base
(require "../descriptor.rkt" "registration.rkt" (for-syntax racket/base syntax/parse))
(provide server)
(define-syntax (server stx)
  (syntax-parse stx
    [(_ #:name name:expr #:version version:expr (~optional (~seq #:instructions instructions:expr) #:defaults ([instructions #'""])))
     #`(begin
         (register-declaration #f #:declaration server name #,stx)
         (let ([descriptor (server-descriptor name version instructions)])
           (register-declaration descriptor) descriptor))]))
