#lang racket/base
(require racket/list racket/string
         "private/workflow-binding-context.rkt" "private/resource-binding.rkt" "private/prompt-binding.rkt"
         (for-template racket/base "private/domain-bindings.rkt"))
(provide (struct-out mcp-binding-info) lookup-mcp-binding require-mcp-binding)

;; Public data only: these values cannot create bindings or carry compiler IR.
(struct mcp-binding-info (kind name arguments) #:transparent)
(define (lookup-mcp-binding id #:space [space 'value])
  (unless (identifier? id) (raise-argument-error 'lookup-mcp-binding "identifier?" id))
  (unless (memq space '(value effect)) (raise-argument-error 'lookup-mcp-binding "(or/c 'value 'effect)" space))
  (unless (syntax-transforming?) (error 'lookup-mcp-binding "only available during syntax expansion"))
  (cond
    [(eq? space 'effect) (and (or (workflow-context-effect? id) (lookup-domain-kind id #:space 'effect))
                            (mcp-binding-info 'effect #f #f))]
    [(workflow-context-binding? id) (mcp-binding-info 'workflow-value #f #f)]
    [else
     (define resource (lookup-resource-binding id))
     (define prompt (and (not resource) (lookup-prompt-binding id)))
     (cond [resource (mcp-binding-info 'resource (resource-binding-name resource) (resource-binding-arguments resource))]
           [prompt (mcp-binding-info 'prompt (prompt-binding-name prompt) (prompt-binding-arguments prompt))]
           [else
            (define kind (lookup-domain-kind id))
            (and kind (mcp-binding-info kind #f #f))])]))
(define (require-mcp-binding id kinds #:space [space 'value] #:context [context id])
  (unless (and (list? kinds) (pair? kinds)
               (andmap (lambda (kind) (memq kind '(schema operation resource prompt effect workflow-value))) kinds))
    (raise-argument-error 'require-mcp-binding "nonempty list of MCP binding kinds" kinds))
  (unless (syntax? context) (raise-argument-error 'require-mcp-binding "syntax?" context))
  (define info (lookup-mcp-binding id #:space space))
  (unless (and info (memq (mcp-binding-info-kind info) kinds))
    (raise-syntax-error 'mcp-extension
      (string-append "expected MCP " (string-join (map symbol->string kinds) " or ") " binding") context id))
  info)
