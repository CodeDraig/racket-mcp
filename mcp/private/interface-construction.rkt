#lang racket/base
(require racket/list "descriptor-types.rkt" "declaration-contract.rkt" "interface-references.rkt"
         "adapter-policy.rkt" "../completion.rkt" "../effect.rkt" "../header-schema.rkt" "../uri-template.rkt"
         (only-in "../authorization.rkt" check-scopes!))
(provide make-interface)
(define (make-interface #:server [server #f] #:tools [tools '()] #:resources [resources '()] #:prompts [prompts '()] #:completions [completions '()] #:requirements [requirements (hasheq)] #:adapter-bindings [adapters (hasheq)] #:references [references (hasheq)] #:adapter-restrictions [restrictions (hasheq)])
  (when server
    (unless (server-descriptor? server) (raise-argument-error 'make-interface "server-descriptor? or #f" server))
    (unless (and (string? (server-descriptor-name server))
                 (string? (server-descriptor-version server))
                 (string? (server-descriptor-instructions server)))
      (error 'make-interface "server name, version and instructions must be strings")))
  (for ([values (in-list (list tools resources prompts completions))]
        [predicate (in-list (list tool-descriptor? resource-descriptor? prompt-descriptor? completion-descriptor?))]
        [kind '(tools resources prompts completions)])
    (unless (and (list? values) (andmap predicate values))
      (error 'make-interface "~a must be a list of matching descriptors" kind)))

  (for ([descriptors (in-list (list tools resources prompts))]
        [arguments-of (in-list (list tool-descriptor-arguments resource-descriptor-arguments prompt-descriptor-arguments))])
    (for ([descriptor (in-list descriptors)])
      (check-arguments! 'make-interface (arguments-of descriptor))))
  (for ([tool (in-list tools)])
    (check-tool-contract! 'make-interface tool)
    (check-tool-input! (tool-descriptor-input-schema tool))
    (header-bindings (tool-descriptor-input-schema tool))
    (check-tool-output! (tool-descriptor-output-schema tool)))
  (for ([prompt (in-list prompts)]) (check-prompt-contract! 'make-interface prompt))
  (for ([resource (in-list resources)])
    (check-resource-contract! 'make-interface resource)
    (check-resource-template! (resource-descriptor-uri resource) (resource-descriptor-arguments resource)))
  (for ([xs (list tools resources prompts)] [name (list tool-descriptor-name resource-descriptor-uri prompt-descriptor-name)])
    (define seen (make-hash))
    (for ([x (in-list xs)]) (when (hash-has-key? seen (name x)) (error 'make-interface "duplicate published identity: ~a" (name x))) (hash-set! seen (name x) #t)))
  (for* ([index (in-range (length resources))]
         [other (in-list (drop resources (add1 index)))])
    (define resource (list-ref resources index))
    (define witness (uri-matchers-overlap (resource-descriptor-matcher resource) (resource-descriptor-matcher other)))
    (when (string? witness)
      (error 'make-interface "overlapping resource URI routes ~a and ~a; both match ~s"
             (resource-descriptor-uri resource) (resource-descriptor-uri other) witness)))
  (define checked-completions (resolve-interface-completions completions resources prompts))
  (unless (hash? requirements) (raise-argument-error 'make-interface "hash?" requirements))
  (define declarations (append tools resources prompts))
  (define checked
    (for/hasheq ([(target scopes) (in-hash requirements)])
      (unless (memq target declarations) (error 'make-interface "scope requirement references an absent declaration"))
      (check-scopes! scopes)
      (values target (remove-duplicates (map string->immutable-string scopes)))))
  (unless (hash? adapters) (raise-argument-error 'make-interface "hash?" adapters))
  (define checked-adapters
    (for/hasheq ([(target bindings) (in-hash adapters)])
      (unless (memq target declarations) (error 'make-interface "adapter binding references an absent declaration"))
      (values target (check-adapter-bindings bindings))))
  (unless (hash? restrictions) (raise-argument-error 'make-interface "hash?" restrictions))
  (define checked-restrictions
    (for/hasheq ([(target allowed) (in-hash restrictions)])
      (unless (memq target declarations) (error 'make-interface "adapter restriction references an absent declaration"))
      (values target (check-allowed-adapters allowed))))
  (unless (hash? references) (raise-argument-error 'make-interface "hash?" references))
  (define checked-references (resolve-interface-references references declarations resources))
  (scoped-interface server tools resources prompts checked-completions checked checked-adapters checked-references checked-restrictions))
