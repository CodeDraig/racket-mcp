#lang racket/base
(require rackunit racket/runtime-path racket/string mcp/private/manifest-diagram mcp/private/manifest-diff)
(module provider racket/base
  (require mcp)
  (provide document)
  (resource (document [id String]) #:uri "remote:///{id}" id)
  (error 'provider "manifest inspection must not instantiate this module"))
(module application mcp/lang
  (require (rename-in (submod ".." provider) [document imported-document]))
  (resource (document [id String]) #:uri "local:///{id}" id)
  (tool (open-local [id String]) (text-result (resource-uri (document id))))
  (tool (open-remote [id String]) (text-result (resource-uri (imported-document id))))
  (error 'application "manifest inspection must not instantiate this module"))
(define-runtime-path self "manifest-reference-bindings.rkt")
(define manifest (dynamic-require `(submod ,self application manifest) 'manifest))
(test-case "same-name resources in other submodules are not local diagram targets"
  (define graph (manifest->mermaid manifest))
  (check-true (string-contains? graph "d1 -.->|references| d0"))
  (check-false (string-contains? graph "d2 -.->|references| d0"))
  (check-true (string-contains? graph "d2 -.->|references| r0")))

(test-case "manifest targets carry lexical local membership"
  (define resource (car manifest))
  (define local (car (hash-ref (cadr manifest) 'resource-references)))
  (define remote (car (hash-ref (caddr manifest) 'resource-references)))
  (check-equal? (hash-ref local 'local-target) (hash-ref resource 'local-id))
  (check-true (hash-has-key? remote 'local-target))
  (check-false (hash-ref remote 'local-target)))
(test-case "diff ignores incidental IDs while retaining local versus external changes"
  (define renamed
    (for/list ([entry (in-list manifest)])
      (define base (if (hash-has-key? entry 'local-id) (hash-set entry 'local-id "renumbered") entry))
      (if (hash-has-key? base 'resource-references)
          (hash-set base 'resource-references
            (for/list ([ref (in-list (hash-ref base 'resource-references))])
              (if (hash-ref ref 'local-target #f) (hash-set ref 'local-target "renumbered") ref)))
          base)))
  (for ([difference (in-list (manifest-diff manifest renamed))])
    (check-equal? (hash-ref difference 'change) "static-manifest-unchanged"))
  (define local (cadr manifest))
  (define external
    (hash-set local 'resource-references
      (list (hash-set (car (hash-ref local 'resource-references)) 'local-target #f))))
  (check-true
    (for/or ([difference (in-list (manifest-diff manifest (list (car manifest) external (caddr manifest))))])
      (equal? (hash-ref difference 'change) "review-required"))))
(test-case "retargeting an ID is visible even when origin hints are unchanged"
  (define original (car manifest))
  (define other (hash-set* original 'name 'other 'local-id "other-resource"))
  (define tool (cadr manifest))
  (define changed
    (hash-set tool 'resource-references
      (list (hash-set (car (hash-ref tool 'resource-references)) 'local-target "other-resource"))))
  (check-true
    (for/or ([difference (in-list (manifest-diff (list original other tool) (list original other changed)))])
      (equal? (hash-ref difference 'change) "review-required")))
  (check-exn #rx"unresolved local resource target"
    (lambda () (manifest-diff (list tool) (list tool)))))

(module generated mcp/lang
  (require (for-syntax racket/base))
  (define-syntax (declarations stx)
    (define name (datum->syntax stx 'generated-resource))
    #`(begin
        (resource (#,name [id String]) #:uri "generated:///{id}" id)
        (tool (generated-open [id String]) (text-result (resource-uri (#,name id))))))
  (declarations)
  (error 'generated "manifest inspection must not instantiate generated handlers"))
(test-case "generated resource identities resolve without matching source locations"
  (define generated-manifest (dynamic-require `(submod ,self generated manifest) 'manifest))
  (define resource (car generated-manifest))
  (define reference (car (hash-ref (cadr generated-manifest) 'resource-references)))
  (check-false (hash-ref reference 'position))
  (check-equal? (hash-ref reference 'local-target) (hash-ref resource 'local-id))
  (check-true (string-contains? (manifest->mermaid generated-manifest) "d1 -.->|references| d0")))
