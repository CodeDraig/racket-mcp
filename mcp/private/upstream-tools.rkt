#lang racket/base
(require "tool-result.rkt" "../descriptor.rkt"
         "../schema.rkt"
         "../json.rkt"
         "../workflow.rkt"
         "../authorization.rkt"
         "../error.rkt"
         "../upstream-bridge.rkt"
         (submod "../upstream-bridge.rkt" private)
         (only-in "../tasks.rkt" current-task-notify)
         "upstream-task-state.rkt"
         "upstream-task-request.rkt"
         "handler-info.rkt"
         "task-observation.rkt"
         "upstream-invocation.rkt")
(provide make-upstream-tools)
(define (make-upstream-tools snapshot request invoke bridge verify-for remap-content)
  (define tasks? (and bridge (hash-has-key?
    (hash-ref (hash-ref (hash-ref snapshot 'server/discover) 'capabilities) 'extensions (hasheq))
    'io.modelcontextprotocol/tasks)))
    (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'tools/list) 'tools))])
      (define schema (hash-ref wire 'inputSchema)) (check-schema! schema)
      (define source (and tasks? (hasheq 'bridge (upstream-bridge-identity bridge) 'name (hash-ref wire 'name))))
      (define (handler bound)
        (define result (invoke "tools/call" (hasheq 'name (hash-ref wire 'name) 'arguments bound) source))
        (if (pending? result) result (hash-set result 'content (map remap-content (hash-ref result 'content)))))
      (define (translate-task-detail result)
        (if (equal? (hash-ref result 'status #f) "completed")
            (let ([value (hash-ref result 'result)])
              (validate-complete-tool-result value (hash-ref wire 'outputSchema #f))
              (hash-set result 'result (hash-set value 'content (map remap-content (hash-ref value 'content))))) result))
      (define (task-dispatch method id params)
        (define context (current-request-context))
        (define principal (request-context-principal context))
        (define credential ((upstream-bridge-credential-id bridge) principal))
        (define notify (current-task-notify))
        (define observation (current-upstream-task-observation))
        (define target (and observation (equal? id (car observation))
                            (task-subscription-target? (cdr observation)) (cdr observation)))
        (define result
          (if target
              (begin
                (unless (equal? (fingerprint bridge snapshot)
                                (fingerprint bridge (task-subscription-target-snapshot target)))
                  (mcp-error -32602 "Subscription snapshot does not match the installed upstream interface"))
                (hasheq 'remoteId
                  (upstream-task-remote-id bridge (current-workflow-store)
                    snapshot id (principal-key principal) credential source)))
              (parameterize ([current-task-notify (lambda (who detail) (notify who (translate-task-detail detail)))])
            (upstream-task-request bridge (current-workflow-store) snapshot request source method id
              #:principal (principal-key principal) #:credential-id credential
              #:responses (hash-ref params 'inputResponses (hasheq)) #:capabilities (request-context-capabilities context)
              #:observed (and (equal? method "tasks/get") observation (equal? id (car observation)) (cdr observation))
              #:validate-detail (lambda (detail) (translate-task-detail detail) (void))
              #:verify (lambda () (verify-for credential)) #:cancelled? (request-context-cancelled? context)))))
        (translate-task-detail result))
      (make-tool (hash-ref wire 'name) '()
                 (if tasks? (bound-task-handler handler (lambda (instance) (upstream-task-matches? instance source)) task-dispatch
                   (lambda (store id principal)
                     (upstream-task-remote-id bridge store snapshot id (principal-key principal)
                       ((upstream-bridge-credential-id bridge) principal) source)))
                     (durable-handler bridge handler))
                 #:description (hash-ref wire 'description "") #:output (hash-ref wire 'outputSchema missing)
                 #:annotations (hash-ref wire 'annotations (hasheq))
                 #:input-schema schema #:raw? #t))
)
