#lang racket/base
(require rackunit racket/list racket/runtime-path racket/string mcp mcp/completion mcp/authorization
         mcp/private/manifest-diff mcp/private/manifest-diagram)
(module provider mcp/lang
  (provide choose)
  (prompt (choose [id String]) (role "user" (text-content id))))
(module consumer mcp/lang
  (require (only-in (submod ".." provider) [choose alias] [mcp-interface imported]))
  (completion (alias id) (lambda (value context) '("chosen")))
  (mount (view imported #:namespace "api/")))
(module filtered mcp/lang
  (require (only-in (submod ".." provider) [mcp-interface imported]))
  (mount (view imported #:exclude '("choose"))))
(module forward racket/base
  (require (only-in (submod ".." filtered) [mcp-interface original]))
  (provide (rename-out [original exported])))
(module restored mcp/lang
  (require (only-in (submod ".." provider) choose [mcp-interface imported]))
  (completion (choose id) (lambda (value context) '("restored")))
  (mount (view imported #:exclude '("choose")))
  (mount (make-interface #:prompts (list choose))))
(module inspection-provider mcp/lang
  (provide choose)
  (prompt (choose [id String]) (error 'handler "must not execute"))
  (error 'provider "must not instantiate"))
(module inspection-consumer mcp/lang
  (require (only-in (submod ".." inspection-provider) choose [mcp-interface imported]))
  (completion (choose id) (lambda (value context) '("unused")))
  (mount (view imported #:namespace "inspect/"))
  (error 'consumer "must not instantiate"))
(define-runtime-path self "prompt-completion-composition.rkt")
(define (complete iface name)
  (hash-ref (hash-ref (dispatch (make-runtime iface) "completion/complete"
                         (hasheq '_meta (request-meta)
                                 'ref (hasheq 'type "ref/prompt" 'name name)
                                 'argument (hasheq 'name "id" 'value ""))) 'completion) 'values))
(test-case "a completion outside a view follows the renamed prompt"
  (check-equal? (complete (dynamic-require `(submod ,self consumer) 'mcp-interface) "api/choose") '("chosen")))
(test-case "the manifest resolves the imported prompt's published name"
  (define entries (dynamic-require `(submod ,self consumer manifest) 'manifest))
  (check-not-false
   (member "(completion (prompt api/choose) id)"
           (map (lambda (entry) (hash-ref entry 'declaration)) (manifest-diff entries entries))))
  (check-true (string-contains? (manifest->mermaid entries) "d0 -.->|completes| d1")))
(test-case "excluding an imported prompt completion target fails expansion"
  (parameterize ([current-namespace (make-base-namespace)])
    (check-exn #rx"prompt removed by a composed view"
      (lambda ()
        (expand (datum->syntax #f
          `(module invalid mcp/lang
             (require (only-in (submod ,self provider) choose [mcp-interface imported]))
             (completion (choose id) (lambda (value context) '("chosen")))
             (mount (view imported #:exclude '("choose"))))))))))
(test-case "nested views and raw interfaces retain the original prompt identity"
  (define base (dynamic-require `(submod ,self provider) 'mcp-interface))
  (define original (car (interface-descriptor-prompts base)))
  (define completed (completion-descriptor original 'id (lambda (value context) '("data"))))
  (define first (view base #:namespace "one/"))
  (define nested (view first #:namespace "two/"))
  (define target (car (interface-descriptor-prompts nested)))
  (define raw (interface-descriptor #f '() '() (list target) (list completed)))
  (check-equal? (complete raw "two/one/choose") '("data"))
  (define resolved (make-interface #:prompts (list target) #:completions (list completed)))
  (check-eq? (completion-descriptor-target (car (interface-descriptor-completions resolved))) target)
  (check-exn #rx"ambiguous mounted prompt"
    (lambda () (make-interface #:prompts (append (interface-descriptor-prompts first) (list target))
                              #:completions (list completed))))
  (check-exn #rx"duplicate completion"
    (lambda () (make-interface #:prompts (list target)
                              #:completions (list completed (struct-copy completion-descriptor completed [target target])))))
  (define unrelated
    (prompt-descriptor (prompt-descriptor-name target) (prompt-descriptor-description target)
                       (prompt-descriptor-arguments target) (prompt-descriptor-handler target)
                       (prompt-descriptor-workflow target)))
  (check-exn #rx"absent prompt"
    (lambda () (make-interface #:prompts (list unrelated) #:completions (list completed)))))
(test-case "a remapped prompt completion retains its required scopes"
  (define base (dynamic-require `(submod ,self provider) 'mcp-interface))
  (define calls 0)
  (define completed (completion-descriptor (car (interface-descriptor-prompts base)) 'id
                      (lambda (value context) (set! calls (add1 calls)) '("allowed"))))
  (define scoped (view base #:namespace "secure/" #:require-scopes '("choose")))
  (define iface (make-interface #:prompts (interface-descriptor-prompts scoped)
                               #:requirements (interface-requirements scoped) #:completions (list completed)))
  (define runtime (make-runtime iface))
  (define params (hasheq '_meta (request-meta) 'ref (hasheq 'type "ref/prompt" 'name "secure/choose")
                         'argument (hasheq 'name "id" 'value "")))
  (define (principal scopes) (verified-principal "reader" "https://issuer.example" "https://api.example" scopes (+ (current-seconds) 60)))
  (check-exn exn:fail:mcp? (lambda () (dispatch runtime "completion/complete" params #:principal (principal '()))))
  (check-equal? calls 0)
  (define result (dispatch runtime "completion/complete" params #:principal (principal '("choose"))))
  (check-equal? (hash-ref (hash-ref result 'completion) 'values) '("allowed"))
  (check-equal? calls 1))
(test-case "re-exported exclusions retain prompt binding identity"
  (parameterize ([current-namespace (make-base-namespace)])
    (check-exn #rx"prompt removed by a composed view"
      (lambda ()
        (expand (datum->syntax #f
          `(module invalid mcp/lang
             (require (only-in (submod ,self provider) choose)
                      (only-in (submod ,self forward) [exported filtered]))
             (completion (choose id) (lambda (value context) '("chosen")))
             (mount filtered))))))))
(test-case "a computed mount can restore an excluded prompt"
  (check-equal? (complete (dynamic-require `(submod ,self restored) 'mcp-interface) "choose") '("restored")))
(test-case "prompt manifests can be inspected without application instantiation"
  (define entries (dynamic-require `(submod ,self inspection-consumer manifest) 'manifest))
  (check-equal? (read (open-input-string (format "~s" entries))) entries)
  (check-equal? (length (manifest-diff entries entries)) 2))
(test-case "prompt completion diffs ignore incidental local IDs and binding names"
  (define entries (dynamic-require `(submod ,self consumer manifest) 'manifest))
  (define changed
    (for/list ([entry entries])
      (define located
        (if (hash-has-key? entry 'local-id)
            (hash-set* entry 'local-id "renumbered"
                       'binding-origin (hash-set (hash-ref entry 'binding-origin) 'binding-name "different-private-name")) entry))
      (if (hash-ref located 'prompt-reference #f)
          (hash-set located 'prompt-reference
            (hash-set* (hash-ref located 'prompt-reference) 'local-target "renumbered" 'binding-name "different-private-name")) located)))
  (for ([change (manifest-diff entries changed)])
    (check-equal? (hash-ref change 'change) "static-manifest-unchanged"))
  (define unresolved
    (for/list ([entry entries])
      (if (hash-ref entry 'prompt-reference #f)
          (hash-set entry 'prompt-reference (hash-set (hash-ref entry 'prompt-reference) 'local-target #f)) entry)))
  (check-not-false (member "review-required" (map (lambda (entry) (hash-ref entry 'change)) (manifest-diff entries unresolved))))
  (check-true (string-contains? (manifest->mermaid unresolved) "external or unresolved prompt")))
(test-case "two views of one completion target are statically ambiguous"
  (parameterize ([current-namespace (make-base-namespace)])
    (check-exn #rx"ambiguous mounted prompt"
      (lambda ()
        (expand (datum->syntax #f
          `(module invalid mcp/lang
             (require (only-in (submod ,self provider) choose [mcp-interface imported]))
             (completion (choose id) (lambda (value context) '("chosen")))
             (mount (view imported #:namespace "one/"))
             (mount (view imported #:namespace "two/")))))))))
(test-case "an imported target is not confused with a same-named local prompt"
  (parameterize ([current-namespace (make-base-namespace)])
    (define expanded
        (expand (datum->syntax #f
          `(module distinct mcp/lang
             (require (only-in (submod ,self provider) [choose imported-choose] [mcp-interface imported]))
             (provide report)
             (prompt (choose [id String]) (role "user" (text-content id)))
             (completion (choose id) (lambda (value context) '("local")))
             (completion (imported-choose id) (lambda (value context) '("remote")))
             (mount (view imported #:namespace "api/"))
             (define (report)
               (define rt (make-runtime mcp-interface))
               (for/list ([name '("choose" "api/choose")])
                 (define result
                   (dispatch rt "completion/complete"
                     (hasheq '_meta (request-meta) 'ref (hasheq 'type "ref/prompt" 'name name)
                             'argument (hasheq 'name "id" 'value ""))))
                 (hash-ref (hash-ref result 'completion) 'values)))))))
    (eval expanded)
    (check-equal? ((dynamic-require ''distinct 'report)) '(("local") ("remote")))))
