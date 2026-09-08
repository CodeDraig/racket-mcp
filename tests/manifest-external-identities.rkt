#lang racket/base
(require rackunit racket/list mcp/private/manifest-diff racket/runtime-path)
(module one racket/base
  (require mcp)
  (provide document)
  (resource (document [id String]) #:uri "one:///{id}" id)
  (error 'one "provider must not instantiate"))
(module two racket/base
  (require mcp)
  (provide document)
  (resource (document [id String]) #:uri "two:///{id}" id)
  (error 'two "provider must not instantiate"))
(module facade racket/base
  (require (rename-in (submod ".." one) [document renamed]))
  (provide renamed))
(module app mcp/lang
  (require (rename-in (submod ".." one) [document first-document])
           (rename-in (submod ".." two) [document second-document])
           (submod ".." facade))
  (tool (read-both [id String])
    (text-result (string-append (resource-uri (first-document id))
                               (resource-uri (second-document id))
                               (resource-uri (renamed id))))))
(define-runtime-path self "manifest-external-identities.rkt")
(define manifest (dynamic-require `(submod ,self app manifest) 'manifest))
(define tool (car manifest))
(define references (hash-ref tool 'resource-references))
(test-case "removing a distinct external submodule reference requires review"
  (check-equal? (length references) 2)
  (define removed (list (hash-set tool 'resource-references (list (car references)))))
  (check-equal? (hash-ref (car (manifest-diff manifest removed)) 'change) "review-required"))
(test-case "re-exports retain the defining provider and aliases deduplicate"
  (check-equal? (length references) 2)
  (define providers (map (lambda (ref) (hash-ref ref 'binding-provider)) references))
  (check-equal? (sort (map (lambda (p) (car (hash-ref p 'submodules))) providers) string<?)
                '("one" "two"))
  (for ([provider (in-list providers)])
    (check-equal? (hash-ref provider 'phase) 0)))
(test-case "moving external declarations does not alter their identity"
  (define moved
    (list (hash-set tool 'resource-references
            (for/list ([ref (in-list references)])
              (hash-set* ref 'line 100 'column 20 'position 500 'span 8)))))
  (check-equal? (hash-ref (car (manifest-diff manifest moved)) 'change)
                "static-manifest-unchanged"))
