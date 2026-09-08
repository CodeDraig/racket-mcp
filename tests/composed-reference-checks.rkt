#lang racket/base
(require rackunit racket/list racket/runtime-path mcp mcp/private/interface-manifest mcp/private/manifest-diff)
(module provider mcp/lang
  (provide document)
  (resource (document [id String]) #:uri "document:///{id}"
    (error 'document "reader must not run during expansion")))
(module colliding-provider mcp/lang
  (require (for-syntax racket/base))
  (define-syntax-rule (make-document exported uri)
    (begin
      (resource (document [id String]) #:uri uri
        (error 'document "reader must not run during inspection"))
      (provide (rename-out [document exported]))))
  (make-document first "first:///{id}")
  (make-document second "second:///{id}"))
(module colliding-app mcp/lang
  (require (only-in (submod ".." colliding-provider) first second [mcp-interface imported]))
  (tool (read-first [id String]) (link (first id)))
  (tool (read-second [id String]) (link (second id)))
  (mount imported))
(module filtered mcp/lang
  (require (only-in (submod ".." provider) [mcp-interface imported]))
  (mount (view imported #:exclude '("document"))))
(module forward racket/base
  (require (only-in (submod ".." filtered) [mcp-interface original]))
  (provide (rename-out [original public])))
(define-runtime-path self "composed-reference-checks.rkt")
(define (expand-app #:instantiate? [instantiate? #f] . forms)
  (parameterize ([current-namespace (make-base-namespace)])
    (define expanded (expand (datum->syntax #f
      `(module application mcp/lang
         (require (only-in (submod ,self provider) document [mcp-interface imported])
                  (only-in (submod ,self forward) [public filtered]))
         (tool (read [id String]) (link (document id)))
         ,@forms)
      (list 'composed-reference-use 21 0 1 1))))
    (if instantiate?
        (let ()
          (eval expanded)
          (define iface (dynamic-require ''application 'mcp-interface))
          ;; Struct types belong to this fresh namespace's module instances.
          ;; Return ordinary wire data instead of crossing its type boundary.
          (list ((dynamic-require 'mcp 'interface-descriptor?) iface)
                (map (dynamic-require 'mcp 'resource-descriptor-uri)
                     ((dynamic-require 'mcp 'interface-descriptor-resources) iface))
                (map (dynamic-require 'mcp 'tool-descriptor-name)
                     ((dynamic-require 'mcp 'interface-descriptor-tools) iface))))
        expanded)))
(define expected-interface '(#t ("document:///{id}") ("read")))
(test-case "a local handler cannot reference a resource removed by its mount"
  (check-exn
   (lambda (e)
     (and (exn:fail:syntax? e) (regexp-match? #rx"removed.*resource|resource.*removed" (exn-message e))
          (ormap (lambda (stx) (equal? (format "~a" (syntax-source stx)) "composed-reference-use")) (exn:fail:syntax-exprs e))))
   (lambda () (expand-app '(mount (view imported #:exclude '("document")))))))
(test-case "a retained resource remains available through a renamed view"
  (check-equal? (expand-app #:instantiate? #t '(mount (view imported #:namespace "api/"))) expected-interface))
(test-case "another static mount can supply the excluded resource"
  (check-equal? (expand-app #:instantiate? #t '(mount (view imported #:exclude '("document"))) '(mount imported)) expected-interface))
(test-case "a computed mount defers the absent-resource decision to runtime"
  (check-equal?
     (expand-app #:instantiate? #t '(mount (view imported #:exclude '("document")))
                 '(mount (make-interface #:resources (list document)))) expected-interface))
(test-case "removed resources remain diagnosed through fragment re-exports"
  (check-exn #rx"references a resource removed by a composed view"
             (lambda () (expand-app '(mount filtered)))))
(test-case "an exclusion is not a permanent ban on another supplying mount"
  (check-equal? (expand-app #:instantiate? #t '(mount filtered) '(mount imported)) expected-interface))
(test-case "two views of one referenced declaration are statically ambiguous"
  (check-exn #rx"references an ambiguous mounted resource"
    (lambda ()
      (expand-app '(mount (view imported #:namespace "one/" #:uris #hash(("document:///{id}" . "one:///{id}"))))
                  '(mount (view imported #:namespace "two/" #:uris #hash(("document:///{id}" . "two:///{id}"))))))))
(test-case "hygienic resources sharing names and source locations retain distinct targets"
  (define entries (dynamic-require `(submod ,self colliding-app manifest) 'manifest))
  (define resources (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'resource)) entries))
  (check-equal? (map (lambda (entry) (hash-ref entry 'name)) resources) '(document document))
  (check-equal? (hash-ref (car resources) 'source) (hash-ref (cadr resources) 'source))
  (check-equal? (hash-ref (car resources) 'position) (hash-ref (cadr resources) 'position))
  (for ([operation '(read-first read-second)] [uri '("first:///{id}" "second:///{id}")])
    (define tool (findf (lambda (entry) (eq? (hash-ref entry 'name) operation)) entries))
    (define resource (findf (lambda (entry) (equal? (hash-ref (hash-ref (hash-ref entry 'metadata) 'uri) 'value) uri)) resources))
    (check-equal? (hash-ref (car (hash-ref tool 'resource-references)) 'local-target) (hash-ref resource 'local-id)))
  (check-true (interface-descriptor? (dynamic-require `(submod ,self colliding-app) 'mcp-interface))))
(test-case "diagnostic source changes do not change lexical resolution"
  (define entries (dynamic-require `(submod ,self colliding-app manifest) 'manifest))
  (define changed
    (for/list ([entry (in-list entries)])
      (if (hash-has-key? entry 'resource-references)
          (hash-set entry 'resource-references
            (for/list ([ref (in-list (hash-ref entry 'resource-references))])
              (hash-set* ref 'local-target #f 'source "different-diagnostic-location" 'position 700))) entry)))
  (define resolved (resolve-mounted-references changed))
  (for ([before (in-list entries)] [after (in-list resolved)] #:when (hash-has-key? before 'resource-references))
    (check-equal? (map (lambda (ref) (hash-ref ref 'local-target)) (hash-ref before 'resource-references))
                  (map (lambda (ref) (hash-ref ref 'local-target)) (hash-ref after 'resource-references)))))
(test-case "missing binding keys cannot establish cross-module identity"
  (define entries (dynamic-require `(submod ,self colliding-app manifest) 'manifest))
  (define old
    (for/list ([entry (in-list entries)])
      (if (hash-has-key? entry 'resource-references)
          (hash-set entry 'resource-references
            (for/list ([ref (in-list (hash-ref entry 'resource-references))])
              (hash-set (hash-remove ref 'binding-name) 'local-target #f))) entry)))
  (for ([entry (in-list (resolve-mounted-references old))] #:when (hash-has-key? entry 'resource-references))
    (for ([ref (in-list (hash-ref entry 'resource-references))]) (check-false (hash-ref ref 'local-target)))))
(test-case "diffs normalize private binding names after public targets resolve"
  (define entries (dynamic-require `(submod ,self colliding-app manifest) 'manifest))
  (define first-tool (findf (lambda (entry) (eq? (hash-ref entry 'name) 'read-first)) entries))
  (define first-resource
    (findf (lambda (entry) (and (eq? (hash-ref entry 'kind) 'resource)
                               (equal? (hash-ref entry 'local-id) (hash-ref (car (hash-ref first-tool 'resource-references)) 'local-target)))) entries))
  (define new-resource (hash-set first-resource 'binding-origin (hash-set (hash-ref first-resource 'binding-origin) 'binding-name 'other-private-name)))
  (define new-tool (hash-set first-tool 'resource-references
                    (map (lambda (ref) (hash-set ref 'binding-name 'other-private-name)) (hash-ref first-tool 'resource-references))))
  (for ([change (in-list (manifest-diff (list first-resource first-tool) (list new-resource new-tool)))])
    (check-equal? (hash-ref change 'change) "static-manifest-unchanged")))
(test-case "unresolved external binding changes require review"
  (define entries (dynamic-require `(submod ,self colliding-app manifest) 'manifest))
  (define tool (findf (lambda (entry) (eq? (hash-ref entry 'name) 'read-first)) entries))
  (define reference (hash-set (car (hash-ref tool 'resource-references)) 'local-target #f))
  (define before (hash-set tool 'resource-references (list reference)))
  (define after (hash-set tool 'resource-references (list (hash-set reference 'binding-name 'another-binding))))
  (check-equal? (hash-ref (car (manifest-diff (list before) (list after))) 'change) "review-required"))

(test-case "module binding keys survive manifest write/read round trips"
  (define entries (dynamic-require `(submod ,self colliding-app manifest) 'manifest))
  (check-equal? (read (open-input-string (format "~s" entries))) entries)
  (for ([entry (in-list entries)] #:when (hash-ref entry 'binding-origin #f))
    (check-true (string? (hash-ref (hash-ref entry 'binding-origin) 'binding-name)))))
