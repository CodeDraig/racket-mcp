#lang racket/base
(require "../workflow.rkt"
         "../subscription.rkt"
         "../error.rkt"
         "../authorization.rkt"
         "../json.rkt"
         "runtime-state.rkt")
(provide run-domain-workflow)
(define (run-domain-workflow rt method principal caps program arguments)
  (unless (runtime-store rt) (mcp-error -32603 "Workflow storage is not configured"))
  (when (and (ormap (lambda (s) (memq (workflow-stage-kind s) '(input input-group))) (workflow-descriptor-stages program))
             (not (hash-has-key? caps 'elicitation)))
    (mcp-error -32021 "Client elicitation capability is required" (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
  (run-workflow (struct-copy workflow-descriptor program [name (string-append method ":" (workflow-descriptor-name program))])
                (runtime-store rt) (for/hasheq ([(key value) (in-hash arguments)] #:unless (missing? value)) (values key value))
                #:principal (principal-key principal) #:state (current-workflow-state)
                #:responses (current-workflow-responses) #:adapters (current-workflow-adapters)
                #:cancelled? (current-cancelled?)))
