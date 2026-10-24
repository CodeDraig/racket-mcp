#lang racket/base
(require "declaration-ir.rkt" "resource-binding.rkt" "prompt-binding.rkt")
(provide completion-target imported-target)
(define (completion-target nodes node)
  (findf (lambda (candidate)
           (and (memq (declaration-node-kind candidate) '(schema shape tool workflow resource prompt))
                (identifier? (declaration-node-name candidate))
                (free-identifier=? (declaration-node-name node) (declaration-node-name candidate)))) nodes))
(define (imported-target node)
  (define id (declaration-node-name node))
  (define resource (lookup-resource-binding id))
  (define prompt (and (not resource) (lookup-prompt-binding id)))
  (cond [resource (hasheq 'kind 'resource 'name (resource-binding-name resource) 'arguments (resource-binding-arguments resource))]
        [prompt (hasheq 'kind 'prompt 'name (prompt-binding-name prompt) 'arguments (prompt-binding-arguments prompt))]
        [else #f]))
