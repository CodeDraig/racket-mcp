#lang racket/base
(require racket/list "descriptor-types.rkt" "handler-info.rkt" "adapter-policy.rkt")
(provide interface-requires-state? interface-effect-summary)
(define (interface-requires-state? interface)
  (for/or ([declarations (in-list (list (interface-descriptor-tools interface)
                                      (interface-descriptor-resources interface)
                                      (interface-descriptor-prompts interface)))]
           [workflow-of (in-list (list tool-descriptor-workflow resource-descriptor-workflow prompt-descriptor-workflow))]
           [handler-of (in-list (list tool-descriptor-handler resource-descriptor-handler prompt-descriptor-handler))])
    (for/or ([declaration (in-list declarations)])
      (or (and (workflow-of declaration) #t)
          (handler-requires-state? (handler-of declaration))))))
(define (interface-effect-summary interface)
  (append-map
    (lambda (declarations kind name-of workflow-of)
      (for/list ([declaration (in-list declarations)])
        (define allowed (hash-ref (interface-adapter-restrictions interface) declaration #f))
        (define summary
          (hasheq 'kind kind 'name (name-of declaration) 'hostEffects "unknown"
                  'declaredAdapters (map symbol->string (declared-adapters (workflow-of declaration)))
                  'adapterPolicy (if allowed "allowlist" "unrestricted")))
        (if allowed (hash-set summary 'allowedAdapters (map symbol->string allowed)) summary)))
    (list (interface-descriptor-tools interface) (interface-descriptor-resources interface) (interface-descriptor-prompts interface))
    '("tool" "resource" "prompt")
    (list tool-descriptor-name resource-descriptor-name prompt-descriptor-name)
    (list tool-descriptor-workflow resource-descriptor-workflow prompt-descriptor-workflow)))
