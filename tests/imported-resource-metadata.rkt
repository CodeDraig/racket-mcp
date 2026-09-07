#lang racket/base
(require rackunit racket/list racket/runtime-path mcp)
(module provider racket/base
  (require mcp)
  (provide document durable)
  (resource (document [id String]) #:uri "doc:///{id}" id)
  (resource (durable [key String]) #:uri "durable:///{key}" #:workflow "1" (text-result key))
  (error 'provider "manifest or expansion must not instantiate the provider"))
(module bridge racket/base
  (require (submod ".." provider))
  (provide (rename-out [document exported])))
(module consumer mcp/lang
  (require (rename-in (submod ".." provider) [document renamed]))
  (completion (renamed id) (error 'handler "manifest must not instantiate handler"))
  (completion (durable key) (error 'handler "manifest must not instantiate handler")))
(require (prefix-in consumer: (submod "." consumer manifest)))
(define entries (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'completion)) consumer:manifest))
(check-equal? (map (lambda (entry) (hash-ref entry 'target)) entries)
              (list (hasheq 'known? #t 'kind 'resource 'name 'document)
                    (hasheq 'known? #t 'kind 'resource 'name 'durable)))
(check-equal? (map (lambda (entry) (hash-ref entry 'argument)) entries) '(id key))
(define-runtime-path self "imported-resource-metadata.rkt")
(define provider `(submod (file ,(path->string self)) provider))
(define bridge `(submod (file ,(path->string self)) bridge))
(define (expanded forms [language 'mcp/lang])
  (expand (datum->syntax #f `(module candidate ,language ,@forms))))
(define (at-typo? e)
  (and (exn:fail:syntax? e) (regexp-match? #rx"unknown target argument" (exn-message e))
       (for/or ([stx (in-list (exn:fail:syntax-exprs e))]) (eq? (syntax-e stx) 'typo))))
(for ([language '(mcp/lang racket/base)])
  (define requires (if (eq? language 'racket/base) '((require mcp)) '()))
  (for ([route (list `(rename-in ,provider [document renamed]) `(rename-in ,bridge [exported renamed]))])
    (check-exn at-typo?
      (lambda () (expanded (append requires `((require ,route) (completion (renamed typo) (error 'handler "not evaluated")))) language)))
    (check-not-exn
      (lambda () (expanded (append requires `((require ,route) (completion (renamed id) (error 'handler "not evaluated")))) language)))))
(check-exn #rx"duplicate statically known published identity"
  (lambda () (expanded `((require (only-in ,provider [document first]) (only-in ,provider [document second]))
                         (completion (first id) values) (completion (second id) values)))))
(check-exn #rx"resource reference expects 1 arguments"
  (lambda () (expanded `((require (only-in ,bridge [exported renamed])) (define bad (renamed))))))
(check-not-exn
  (lambda () (expanded '((completion (later id) values) (resource (later [id String]) #:uri "later:///{id}" id)))))
(check-not-exn
  (lambda () (expanded `((require (only-in ,provider [document renamed]))
                         (let ([renamed 'host]) (completion (renamed typo) values))))))
