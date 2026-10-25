#lang racket/base
(require "runtime-binding.rkt" "runtime-state.rkt"
         "runtime-policy.rkt"
         "runtime-render.rkt"
         "embedded-content.rkt"
         "../descriptor.rkt"
         "../workflow.rkt"
         (submod "../workflow.rkt" private)
         "../error.rkt")
(provide dispatch-prompt-get)
(define (dispatch-prompt-get rt params render-call run-domain-workflow)
  (define iface (runtime-interface rt))
  (define d (lookup-operation (interface-descriptor-prompts iface) prompt-descriptor-name params 'name))
  (define input (hash-ref params 'arguments (hasheq)))
  (unless (and (hash? input) (for/and ([value (in-hash-values input)]) (string? value))) (mcp-error -32602 "Prompt arguments must be strings"))
  (define program
    (and (prompt-descriptor-workflow d)
         (workflow-add-fingerprint-suffix (prompt-descriptor-workflow d)
                                          (string-append ":prompt-codecs:" (prompt-codec-fingerprint d)))))
  (define arguments (bind-call-arguments rt "prompts/get" params (prompt-descriptor-arguments d) input program
    (if program (workflow-executable-fingerprint program (current-workflow-adapters)) (string-append "render/1:" (prompt-codec-fingerprint d)))))
  (define messages (render-call (lambda () (if program
                       (run-domain-workflow program arguments)
                       ((prompt-descriptor-handler d) arguments)))
                                (if program (workflow-executable-fingerprint program (current-workflow-adapters)) (string-append "render/1:" (prompt-codec-fingerprint d)))))
  (cond [(input-required? messages) messages]
        [(and (hash? messages) (equal? (hash-ref messages 'resultType #f) "complete")
              (list? (hash-ref messages 'messages #f)))
         (hash-set messages 'messages (expand-prompt-messages (hash-ref messages 'messages)))]
        [else (unless (list? messages) (mcp-error -32603 "Prompt renderer must return messages"))
              (hasheq 'resultType "complete" 'messages (expand-prompt-messages messages))])
)
