#lang racket/base
(require "../schema.rkt"
         "../codec.rkt"
         "domain-bindings.rkt"
         "registration.rkt"
         (for-syntax racket/base racket/syntax syntax/parse "declaration-syntax.rkt"))
(provide shape)
(define-syntax (shape stx)
  (syntax-parse stx
    [(_ name:id [field:id spec:expr] ...)
     (check-binders (syntax->list #'(field ...)) stx)
     (check-wire-binders! (syntax->list #'(field ...)))
     (for-each check-literal-schema! (syntax->list #'(spec ...)))
     (define internal (car (generate-temporaries #'(name))))
     (with-syntax ([record internal] [constructor (format-id #'name "make-~a" #'name)]
                   [encoder (format-id #'name "~a->json" #'name)] [decoder (format-id #'name "json->~a" #'name)] [codec (format-id #'name "~a-codec" #'name)]
                   [(accessor ...) (for/list ([f (in-list (syntax->list #'(field ...)))]) (format-id #'name "~a-~a" #'name f))]
                   [(internal-accessor ...) (for/list ([f (in-list (syntax->list #'(field ...)))]) (format-id internal "~a-~a" internal f))])
       #`(begin (struct record (field ...) #:transparent)
                (define-schema-value name (object-schema (make-immutable-hasheq (list (cons 'field (checked-schema-expression spec)) ...))))
                (define (constructor field ...)
                  (define v (record field ...)) (encoder v) v)
                (define accessor internal-accessor) ...
                (define (encoder v)
                  (define data (make-immutable-hasheq (list (cons 'field (internal-accessor v)) ...)))
                  (unless (valid? name data) (error 'encoder "shape failed its schema")) data)
                (define (decoder data)
                  (unless (valid? name data) (error 'decoder "shape failed its schema"))
                  (record (hash-ref data 'field) ...))
                (define codec (make-value-codec (symbol->string 'name) "1" name encoder decoder))
                (register-declaration #f #:declaration shape name #,stx)))]))
