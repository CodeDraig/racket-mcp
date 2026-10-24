#lang racket/base
(require racket/list
         syntax/parse
         "../uri-template.rkt"
         (only-in "../schema.rkt" check-schema!)
         (for-template racket/base "descriptor-types.rkt" "domain-bindings.rkt"))
(provide arg prompt-arg check-literal-uri! check-literal-schema! check-wire-binders! argument-code check-binders)
(define (check-literal-uri! uri ids)
  (define text (syntax-parse uri #:literals (quote)
                 [text:str (syntax-e #'text)] [(quote text:str) (syntax-e #'text)] [_ #f]))
  (when text
    (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'resource (exn-message e) uri))])
      (for ([variable (in-list (uri-template-variables text))])
        (unless (memq variable (map syntax-e ids))
          (error 'resource "URI template references an undeclared argument: ~a" variable))))))
;; Inspect only reader literals and the lexically bound Racket quote form.
;; Computed schemas retain ordinary expression evaluation at instantiation.
(define (check-literal-schema! value)
  (define datum (syntax-e value))
  (define literal
    (syntax-parse value #:literals (quote)
      [(quote datum) (cons #t (syntax->datum #'datum))]
      [_ (and (or (boolean? datum) (hash? datum) (string? datum) (number? datum)
                  (bytes? datum) (char? datum) (vector? datum)
                  (regexp? datum) (byte-regexp? datum) (box? datum)
                  (prefab-struct-key datum))
              (cons #t (syntax->datum value)))]))
  (when literal
    (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'schema (exn-message e) value))])
      (check-schema! (cdr literal)))))
(define-syntax-class arg
  #:attributes (id spec optional default)
  (pattern [id:id spec:expr] #:attr optional #'#f #:attr default #f)
  (pattern [id:id spec:expr #:optional] #:attr optional #'#t #:attr default #f)
  (pattern [id:id spec:expr #:default default:expr] #:attr optional #'#t))
(define-syntax-class prompt-arg
  #:attributes (id spec optional default codec)
  (pattern a:arg #:attr id #'a.id #:attr spec #'a.spec #:attr optional #'a.optional #:attr default (attribute a.default) #:attr codec #f)
  (pattern [id:id spec:expr #:codec codec:expr] #:attr optional #'#f #:attr default #f)
  (pattern [id:id spec:expr #:codec codec:expr #:optional] #:attr optional #'#t #:attr default #f)
  (pattern [id:id spec:expr #:codec codec:expr #:default default:expr] #:attr optional #'#t))
;; Lexical identity and JSON field identity differ. Distinct scopes can bind
;; the same printed name, but the peer sends only the interned JSON name.
(define (check-wire-binders! ids)
  (define seen (make-hasheq))
  (for ([id (in-list ids)])
    (define name (syntax-e id))
    (unless (symbol-interned? name)
      (raise-syntax-error #f "declaration wire name must be an interned symbol" id))
    (when (hash-has-key? seen name)
      (raise-syntax-error #f "duplicate declaration wire name" id))
    (hash-set! seen name #t)))
(define (argument-code ids specs opts defaults [codecs (make-list (length ids) #f)])
  (check-wire-binders! ids)
  (for/list ([id ids] [spec specs] [opt opts] [default defaults] [codec codecs] [i (in-naturals)])
    (check-literal-schema! spec)
    #`(#,(if codec #'prompt-argument #'argument) '#,id (checked-schema-expression #,spec) #,opt
                #,(if default
                      #`(lambda (previous)
                          (let (#,@(for/list ([earlier (in-list (take ids i))]) #`[#,earlier (hash-ref previous '#,earlier)])) #,default)) #'#f) #,@(if codec (list codec) '()))))
(define (check-binders ids stx)
  (define duplicate (check-duplicate-identifier ids))
  (when duplicate (raise-syntax-error #f "duplicate argument binder" stx duplicate)))
