#lang racket/base
(require rackunit racket/list racket/runtime-path mcp mcp/completion
         mcp/private/manifest-diagram mcp/private/manifest-docs mcp/private/manifest-diff)
(module fragment mcp/lang
  (resource (document [id String]) #:uri "document:///{id}"
    (error 'document "inspection must not execute readers"))
  (tool (read-document [id String]) (link (document id)))
  (error 'fragment "inspection must not instantiate fragments"))
(module forward racket/base
  (require (only-in (submod ".." fragment) [mcp-interface original]))
  (provide (rename-out [original exported])))
(module app mcp/lang
  (require (only-in (submod ".." forward) [exported imported]))
  (mount imported)
  (error 'app "inspection must not instantiate applications"))
(module transformed mcp/lang
  (require (only-in (submod ".." forward) [exported imported]))
  (mount (view imported #:namespace "api/" #:rename #hash(("read-document" . "read"))
               #:uris #hash(("document:///{id}" . "api:///{id}"))
               #:require-scopes '("documents:read")))
  (error 'transformed "inspection must not instantiate views"))
(module dynamic mcp/lang
  (require (only-in (submod ".." forward) [exported imported]))
  (mount (view imported #:namespace (error 'namespace "must not evaluate metadata"))))
(module runtime-fragment mcp/lang
  (provide document evaluations)
  (define count 0)
  (define (evaluations) count)
  (resource (document [id String]) #:uri "runtime:///{id}" "body")
  (completion (document id) (lambda (value context) '("one")))
  (tool (read-document [id String])
    #:description (begin (set! count (add1 count)) "Read")
    (link (document id))))
(module runtime-app mcp/lang
  (require (only-in (submod ".." runtime-fragment) [mcp-interface imported] document))
  (tool (local-read [id String]) (link (document id)))
  (mount (view imported #:namespace "v/" #:uris (hash "runtime:///{id}" "v:///{id}"))))
(module conditional mcp/lang
  (require (only-in (submod ".." runtime-fragment) [mcp-interface imported]))
  (when #f (mount imported)))
(module nested mcp/lang
  (require (only-in (submod ".." app) [mcp-interface imported]))
  (mount (mount-interfaces (view imported #:exclude (list "read-document")))))
(module overlap-fragment mcp/lang
  (resource (fixed) #:uri "document:///fixed" "body"))
(module renamed-view mcp/lang
  (require (only-in mcp/composition [view select])
           (only-in (submod ".." fragment) [mcp-interface imported]))
  (mount (select imported #:namespace "renamed/")))
(module shadowed-view mcp/lang
  (require (only-in (submod ".." fragment) [mcp-interface imported]))
  (define (view iface) (error 'view "host helper must not run during inspection"))
  (mount (view imported)))
(module dynamic-policy mcp/lang
  (require (only-in (submod ".." fragment) [mcp-interface imported]))
  (mount (view imported #:require-scopes (error 'policy "must not evaluate policies"))))
(define-runtime-path self "manifest-composition.rkt")
(define manifest (dynamic-require `(submod ,self app manifest) 'manifest))
(test-case "mounted declarations survive renamed re-exports without instantiation"
  (check-equal? (map (lambda (entry) (hash-ref entry 'kind)) manifest) '(resource tool))
  (check-equal? (map (lambda (entry) (hash-ref entry 'name)) manifest) '(document read-document)))
(test-case "mounted resource references retain local identity"
  (define resource (findf (lambda (entry) (eq? (hash-ref entry 'kind) 'resource)) manifest))
  (define tool (findf (lambda (entry) (eq? (hash-ref entry 'kind) 'tool)) manifest))
  (check-not-false resource)
  (check-not-false tool)
  (when (and resource tool)
    (check-equal? (hash-ref (car (hash-ref tool 'resource-references)) 'local-target)
                  (hash-ref resource 'local-id))))
(test-case "documentation and diagrams include the mounted surface"
  (check-true (regexp-match? #rx"read-document" (manifest->markdown manifest)))
  (check-true (regexp-match? #rx"references" (manifest->mermaid manifest))))
(test-case "literal views rename wire identities, URI templates and retain policy metadata"
  (define entries (dynamic-require `(submod ,self transformed manifest) 'manifest))
  (check-equal? (map (lambda (entry) (hash-ref entry 'name)) entries) '(api/document api/read))
  (check-equal? (hash-ref (hash-ref (hash-ref (car entries) 'metadata) 'uri) 'value) "api:///{id}")
  (check-equal? (hash-ref (hash-ref (car (hash-ref (cadr entries) 'composition-policies)) 'require-scopes) 'value)
                '("documents:read"))
  (check-equal? (hash-ref (car (hash-ref (cadr entries) 'resource-references)) 'local-target)
                (hash-ref (car entries) 'local-id)))
(test-case "dynamic views are explicit and never evaluated for inspection"
  (define entries (dynamic-require `(submod ,self dynamic manifest) 'manifest))
  (check-equal? (length entries) 1)
  (check-equal? (hash-ref (car entries) 'kind) 'mount)
  (check-false (hash-ref (car entries) 'known?))
  (check-true (regexp-match? #rx"must not evaluate metadata" (hash-ref (car entries) 'expression)))
  (check-true (regexp-match? #rx"Dynamic interface expression" (manifest->markdown entries)))
  (for ([report (list (manifest-diff entries entries) (manifest-diff entries '()) (manifest-diff '() entries))])
    (check-equal? (hash-ref (car report) 'change) "review-required")))
(test-case "conditional mounts are not claimed as installed declarations"
  (define entries (dynamic-require `(submod ,self conditional manifest) 'manifest))
  (check-equal? (map (lambda (entry) (hash-ref entry 'kind)) entries) '(mount))
  (check-equal? (interface-descriptor-tools (dynamic-require `(submod ,self conditional) 'mcp-interface)) '()))
(test-case "nested interface composition preserves selected resources"
  (define entries (dynamic-require `(submod ,self nested manifest) 'manifest))
  (check-equal? (map (lambda (entry) (hash-ref entry 'name)) entries) '(document)))
(test-case "renamed view bindings retain static transformation semantics"
  (define entries (dynamic-require `(submod ,self renamed-view manifest) 'manifest))
  (check-equal? (map (lambda (entry) (hash-ref entry 'name)) entries) '(renamed/document renamed/read-document)))
(test-case "a host binding named view is not interpreted as the DSL view"
  (define entries (dynamic-require `(submod ,self shadowed-view manifest) 'manifest))
  (check-equal? (map (lambda (entry) (hash-ref entry 'kind)) entries) '(mount)))
(test-case "computed view policies mark the declaration metadata dynamic"
  (define entries (dynamic-require `(submod ,self dynamic-policy manifest) 'manifest))
  (check-equal? (map (lambda (entry) (hash-ref entry 'kind)) entries) '(resource tool))
  (for ([entry (in-list entries)])
    (check-true (hash-ref entry 'dynamic-metadata))
    (check-false (hash-ref (hash-ref (car (hash-ref entry 'composition-policies)) 'require-scopes) 'known?))))
(test-case "runtime and composed metadata agree; descriptor expressions execute once"
  (define entries (dynamic-require `(submod ,self runtime-app manifest) 'manifest))
  (define iface (dynamic-require `(submod ,self runtime-app) 'mcp-interface))
  (check-true (interface-descriptor? iface))
  (check-equal? ((dynamic-require `(submod ,self runtime-fragment) 'evaluations)) 1)
  (check-equal? (map tool-descriptor-name (interface-descriptor-tools iface))
                (map (lambda (entry) (symbol->string (hash-ref entry 'name)))
                     (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'tool)) entries)))
  (define completed (findf (lambda (entry) (eq? (hash-ref entry 'kind) 'completion)) entries))
  (check-equal? (hash-ref (hash-ref completed 'target) 'name) 'v/document)
  (check-equal? (resource-descriptor-uri (completion-descriptor-target (car (interface-descriptor-completions iface)))) "v:///{id}"))
(test-case "local handler references resolve through mounted declaration origins"
  (define entries (dynamic-require `(submod ,self runtime-app manifest) 'manifest))
  (define resource (findf (lambda (entry) (eq? (hash-ref entry 'kind) 'resource)) entries))
  (define local (findf (lambda (entry) (eq? (hash-ref entry 'name) 'local-read)) entries))
  (check-equal? (hash-ref (car (hash-ref local 'resource-references)) 'local-target) (hash-ref resource 'local-id))
  (check-false (regexp-match? #rx"external or unresolved" (manifest->mermaid entries))))
(define (expand-mount form)
  (parameterize ([current-namespace (make-base-namespace)])
    (expand (datum->syntax #f
      `(module rejected mcp/lang
         (require (only-in (submod ,self fragment) [mcp-interface imported])
                  (only-in (submod ,self overlap-fragment) [mcp-interface second]))
         ,form) (list 'composed-fixture 17 0 1 1)))))
(for ([case (in-list
             (list (cons '(mount imported imported) #rx"duplicate statically known")
                   (cons '(mount (view imported #:exclude '("read-document")) second) #rx"overlapping resource URI routes")
                   (cons '(mount (view imported #:exclude '("document"))) #rx"removed a referenced resource")
                   (cons '(mount (view imported #:namespace 42)) #rx"invalid literal")
                   (cons '(mount (view imported #:uris #hash(("document:///{id}" . "api:///{other}")))) #rx"preserve template variables")))])
  (test-case (format "invalid composition: ~s" (car case))
    (check-exn (lambda (e) (and (exn:fail:syntax? e) (regexp-match? (cdr case) (exn-message e))
                              (ormap (lambda (s) (equal? (syntax-source s) 'composed-fixture)) (exn:fail:syntax-exprs e))))
               (lambda () (expand-mount (car case))))))
