#lang racket/base
(require rackunit racket/list racket/runtime-path mcp mcp/completion
         mcp/private/manifest-diff)
(module provider mcp/lang
  (require (for-syntax racket/base))
  (define-syntax-rule (declare-resource uri answer)
    (begin
      (resource (document [id String]) #:uri uri "body")
      (completion (document id) (lambda (value context) (list answer)))))
  (define-syntax-rule (declare-prompt)
    (begin
      (prompt (document [id String]) "body")
      (completion (document id) (lambda (value context) '("prompt")))))
  (declare-resource "first:///{id}" "first")
  (declare-resource "second:///{id}" "second")
  (declare-prompt))
(module mounted mcp/lang
  (require (only-in (submod ".." provider) [mcp-interface imported]))
  (mount (view imported #:namespace "api/"
               #:uris #hash(("first:///{id}" . "changed:///{id}")))))
(module target-provider mcp/lang
  (provide document)
  (resource (document [id String]) #:uri "external:///{id}" "body"))
(module imported-completion mcp/lang
  (require (only-in (submod ".." target-provider) [document alias] [mcp-interface imported]))
  (completion (alias id) (lambda (value context) '("external")))
  (mount (view imported #:namespace "external/"
               #:uris #hash(("external:///{id}" . "mapped:///{id}")))))
(define-runtime-path self "manifest-completion-identities.rkt")
(define (manifest part) (dynamic-require `(submod ,self ,part manifest) 'manifest))
(test-case "same-named prompt and resource completions have distinct identities"
  (define entries (manifest 'provider))
  (define result (manifest-diff entries entries))
  (check-equal? (length result) 6)
  (check-true (andmap (lambda (entry) (equal? (hash-ref entry 'change) "static-manifest-unchanged")) result)))
(test-case "mounted resource completions resolve to transformed URIs"
  (define entries (manifest 'mounted))
  (define result (manifest-diff entries entries))
  (check-equal? (length result) 6)
  (define identities (map (lambda (entry) (hash-ref entry 'declaration)) result))
  (check-not-false (member "(completion (resource changed:///{id}) id)" identities))
  (check-not-false (member "(completion (resource second:///{id}) id)" identities))
  (check-not-false (member "(completion (prompt api/document) id)" identities))
  (define iface (dynamic-require `(submod ,self mounted) 'mcp-interface))
  (check-equal? (length (interface-descriptor-completions iface)) 3)
  (define runtime (make-runtime iface))
  (for ([ref (list (hasheq 'type "ref/resource" 'uri "changed:///{id}")
                   (hasheq 'type "ref/resource" 'uri "second:///{id}")
                   (hasheq 'type "ref/prompt" 'name "api/document"))]
        [expected '("first" "second" "prompt")])
    (check-equal? (hash-ref (hash-ref (dispatch runtime "completion/complete"
                               (hasheq '_meta (request-meta) 'ref ref
                                       'argument (hasheq 'name "id" 'value ""))) 'completion) 'values)
                  (list expected))))
(test-case "duplicate completions are rejected by resolved target and argument"
  (define entries (manifest 'provider))
  (define completed (findf (lambda (entry) (eq? (hash-ref entry 'kind) 'completion)) entries))
  (check-exn #rx"duplicate declaration identity"
             (lambda () (manifest-diff entries (cons (hash-set completed 'name 'alias) entries)))))
(test-case "legacy unresolved targets are explicit review items"
  (define entries (manifest 'provider))
  (define legacy
    (for/list ([entry entries])
      (if (eq? (hash-ref entry 'kind) 'completion)
          (hash-remove entry 'resource-references) entry)))
  (define result (manifest-diff legacy legacy))
  (check-equal? (count (lambda (entry) (equal? (hash-ref entry 'change) "review-required")) result) 2))
(test-case "renamed imported bindings resolve through a transformed mount"
  (define entries (manifest 'imported-completion))
  (define results (manifest-diff entries entries))
  (check-not-false (member "(completion (resource mapped:///{id}) id)"
                          (map (lambda (entry) (hash-ref entry 'declaration)) results)))
  (define iface (dynamic-require `(submod ,self imported-completion) 'mcp-interface))
  (check-equal?
   (hash-ref (hash-ref (dispatch (make-runtime iface) "completion/complete"
                          (hasheq '_meta (request-meta)
                                  'ref (hasheq 'type "ref/resource" 'uri "mapped:///{id}")
                                  'argument (hasheq 'name "id" 'value ""))) 'completion) 'values)
   '("external")))
(test-case "excluding an imported completion target is diagnosed during expansion"
  (parameterize ([current-namespace (make-base-namespace)])
    (check-exn #rx"resource removed by a composed view"
      (lambda ()
        (expand (datum->syntax #f
          `(module invalid mcp/lang
             (require (only-in (submod ,self target-provider) document [mcp-interface imported]))
             (completion (document id) (lambda (value context) '("external")))
             (mount (view imported #:exclude '("document"))))))))))
(test-case "duplicate completion targets are checked after mount resolution"
  (parameterize ([current-namespace (make-base-namespace)])
    (check-exn #rx"duplicate statically known published identity"
      (lambda ()
        (expand (datum->syntax #f
          '(module invalid mcp/lang
             (module provider mcp/lang
               (provide document)
               (resource (document [id String]) #:uri "document:///{id}" "body")
               (completion (document id) (lambda (value context) '("provider"))))
             (require (only-in (submod "." provider) document [mcp-interface imported]))
             (completion (document id) (lambda (value context) '("consumer")))
             (mount (view imported #:namespace "api/")))))))))
(test-case "data API resolves unique resource identities and rejects ambiguity"
  (define base (dynamic-require `(submod ,self target-provider) 'mcp-interface))
  (define original (car (interface-descriptor-resources base)))
  (define completed (completion-descriptor original 'id (lambda (value context) '("result"))))
  (define first-view (view base #:namespace "one/" #:uris (hash "external:///{id}" "one:///{id}")))
  (define first (car (interface-descriptor-resources first-view)))
  (define resolved (make-interface #:resources (list first) #:completions (list completed)))
  (check-eq? (completion-descriptor-target (car (interface-descriptor-completions resolved))) first)
  (define raw (interface-descriptor #f '() (list first) '() (list completed)))
  (define runtime (make-runtime raw))
  (check-eq? (completion-descriptor-target
              (car (interface-descriptor-completions (runtime-interface runtime)))) first)
  (check-equal?
   (hash-ref (hash-ref (dispatch runtime "completion/complete"
                          (hasheq '_meta (request-meta)
                                  'ref (hasheq 'type "ref/resource" 'uri "one:///{id}")
                                  'argument (hasheq 'name "id" 'value ""))) 'completion) 'values)
   '("result"))
  (check-eq? (runtime-interface (make-runtime resolved)) resolved)
  (define second (car (interface-descriptor-resources
                      (view base #:namespace "two/" #:uris (hash "external:///{id}" "two:///{id}")))))
  (check-exn #rx"ambiguous mounted resource"
             (lambda () (make-interface #:resources (list first second) #:completions (list completed))))
  (check-exn #rx"duplicate completion"
             (lambda () (make-interface #:resources (list first)
                         #:completions (list completed (struct-copy completion-descriptor completed [target first])))))
  (check-exn #rx"absent resource"
             (lambda () (make-interface
                         #:resources (list (struct-copy resource-descriptor first [identity (gensym 'different)]))
                         #:completions (list completed)))))
