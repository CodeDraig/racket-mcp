#lang racket/base
(require rackunit racket/list racket/runtime-path mcp)
(module provider racket/base
  (require mcp)
  (provide document durable)
  (prompt (document [id String]) (role "user" (text-content id)))
  (prompt (durable [key String]) #:workflow "1" (text-result key))
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
              (list (hasheq 'known? #t 'kind 'prompt 'name 'document)
                    (hasheq 'known? #t 'kind 'prompt 'name 'durable)))
(check-equal? (map (lambda (entry) (hash-ref entry 'argument)) entries) '(id key))
(define-runtime-path self "imported-prompt-metadata.rkt")
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
(check-not-exn
  (lambda () (expanded '((completion (later id) values) (prompt (later [id String]) (role "user" (text-content id)))))))
(check-not-exn
  (lambda () (expanded `((require (only-in ,provider [document renamed]))
                         (let ([renamed 'host]) (completion (renamed typo) values))))))

(module live-provider racket/base
  (require mcp)
  (provide greeting)
  (prompt (greeting [name String]) (role "user" (text-content name))))
(require (rename-in (submod "." live-provider) [greeting imported-greeting])
         "../mcp/private/domain-bindings.rkt")
(check-eq? (operation-reference imported-greeting) imported-greeting)
(check-equal? (prompt-descriptor-name imported-greeting) "greeting")
(check-eq? (dynamic-require `(submod ,self live-provider) 'greeting) imported-greeting)
(check-exn #rx"expected a schema"
  (lambda () (expanded `((require (only-in (submod (file ,(path->string self)) live-provider) greeting))
                         (schema Bad greeting)))))
(check-exn exn:fail:syntax?
  (lambda () (expanded `((require (only-in (submod (file ,(path->string self)) live-provider) greeting))
                         (set! greeting #f)))))
(module phase-user racket/base
  (require (for-syntax racket/base mcp (submod ".." live-provider)))
  (provide baked)
  (define-syntax (name stx) #`'#,(prompt-descriptor-name greeting))
  (define baked (name)))
(require (submod "." phase-user))
(check-equal? baked "greeting")
