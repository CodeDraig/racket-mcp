#lang racket/base
(require (for-template racket/base))
(provide (struct-out interface-binding) lookup-interface-manifest)
;; Runtime use denotes the ordinary interface descriptor. Static consumers read
;; only the generated independent manifest submodule of this defining binding.
(struct interface-binding (target)
  #:property prop:procedure
  (lambda (self stx)
    (syntax-case stx ()
      [id (identifier? #'id) (interface-binding-target self)]
      [(_ . arguments) #`(#,(interface-binding-target self) . arguments)])))
(define (provider-root index)
  (define name (resolved-module-path-name (module-path-index-resolve index)))
  (define root (if (pair? name) (car name) name))
  (hasheq 'kind (if (path? root) "file" "symbol")
          'module (if (path? root) (path->string root) (symbol->string root))))
(define (rebase-manifest entries old actual)
  (define (origin value)
    (define provider (and value (hash-ref value 'binding-provider #f)))
    (if (and provider old (equal? (hash-ref provider 'kind) (hash-ref old 'kind))
             (equal? (hash-ref provider 'module) (hash-ref old 'module)))
        (hash-set value 'binding-provider
          (hash-set* provider 'kind (hash-ref actual 'kind) 'module (hash-ref actual 'module))) value))
  (for/list ([entry (in-list entries)])
    (define located (if (hash-has-key? entry 'binding-origin) (hash-set entry 'binding-origin (origin (hash-ref entry 'binding-origin))) entry))
    (if (hash-has-key? located 'resource-references)
        (hash-set located 'resource-references (map origin (hash-ref located 'resource-references))) located)))
(define (lookup-interface-manifest id)
  (and (identifier? id)
       (let ([binding (syntax-local-value id (lambda () #f))])
         (and (interface-binding? binding)
              (let* ([origin (identifier-binding id)]
                     [resolved (module-path-index-resolve
                                (module-path-index-join '(submod "." manifest) (car origin)))]
                     [name (resolved-module-path-name resolved)]
                     [path (if (and (pair? name) (path? (car name)))
                               `(submod ,@name) resolved)])
                (define-values (relative base) (module-path-index-split (car origin)))
                (and relative (module-declared? path #t)
                     (rebase-manifest (dynamic-require path 'manifest)
                                      (dynamic-require path 'manifest-provider)
                                      (provider-root (car origin)))))))))
