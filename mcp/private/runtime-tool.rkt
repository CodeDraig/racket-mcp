#lang racket/base
(require "../subscription.rkt" "../json.rkt" "runtime-binding.rkt" "task-context.rkt" "tool-result.rkt" "runtime-state.rkt"
         "runtime-policy.rkt"
         "runtime-changes.rkt"
         "handler-info.rkt"
         "embedded-content.rkt"
         "../descriptor.rkt"
         "../workflow.rkt"
         "../tasks.rkt"
         "../freshness.rkt"
         "../schema.rkt"
         "../error.rkt"
         "../authorization.rkt")
(provide dispatch-tool-call)
(define (dispatch-tool-call rt params render-call executor)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (define d (lookup-operation (interface-descriptor-tools iface) tool-descriptor-name params 'name))
  (define args (hash-ref params 'arguments (hasheq)))
  (define worker? (eq? d (current-task-resumption)))
  (unless (or worker? (valid? (tool-descriptor-input-schema d) args)) (mcp-error -32602 "Invalid tool arguments"))
  (define bound (if (tool-descriptor-raw? d) args (if worker? args (bind-call-arguments rt "tools/call" params (tool-descriptor-arguments d) args (tool-descriptor-workflow d) (if (tool-descriptor-workflow d) (workflow-executable-fingerprint (tool-descriptor-workflow d) (current-workflow-adapters)) "render/1")))))
  (define task? (and (not worker?) (or (eq? (tool-descriptor-execution d) 'task)
                    (and (eq? (tool-descriptor-execution d) 'task-optional)
                         (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)))))
  (when (and task? (not (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)))
    (mcp-error -32021 "Client Tasks capability is required" (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
  (when (and (not worker?) (tool-descriptor-workflow d)
             (ormap (lambda (s) (memq (workflow-stage-kind s) '(input input-group))) (workflow-descriptor-stages (tool-descriptor-workflow d)))
             (not (hash-has-key? caps 'elicitation))) (mcp-error -32021 "Client elicitation capability is required" (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
  (define (invoke-handler)
    (define outcome (parameterize ([current-task-resumption #f]) ((tool-descriptor-handler d) bound)))
    (cond [(committed-result? outcome)
           (define value (committed-result-result outcome))
           (unless (and (hash? value) (equal? (hash-ref value 'resultType #f) "complete")
                        (not (hash-ref value 'isError #f)))
             (mcp-error -32603 "A commit acknowledgement requires a successful complete result"))
           (define keys (change-keys! (append (change-keys! (committed-result-keys outcome))
                                            (change-keys! ((tool-descriptor-changes d) bound value)))))
           (unless (null? keys)
             (if (runtime-store rt)
                 (begin (record-committed-change! (runtime-store rt) (principal-key principal) keys)
                        (runtime-drain-changes! rt))
                 (runtime-report-change! rt principal keys)))
           value]
          [else outcome]))
  (when worker? (current-render-bindings bound))
       (define result
         (parameterize ([current-task-resumption #f])
           (render-call
            (lambda ()
              (cond
                [worker?
                 (run-workflow (tool-descriptor-workflow d) (runtime-store rt)
                   (for/hasheq ([(key value) (in-hash bound)] #:unless (missing? value)) (values key value))
                   #:principal (principal-key principal) #:state (current-workflow-state)
                   #:responses (current-workflow-responses) #:adapters (current-workflow-adapters)
                   #:cancelled? (current-cancelled?))]
                [task?
                 (unless (runtime-store rt) (mcp-error -32603 "Task storage is not configured"))
                 (parameterize ([current-task-executor executor])
                   (start-workflow-task (tool-descriptor-workflow d) (runtime-store rt) bound (principal-key principal)
                     #:output-schema (tool-descriptor-output-schema d)
                     #:state (current-workflow-state) #:responses (current-workflow-responses)
                     #:operation-name (tool-descriptor-name d) #:adapters (current-workflow-adapters) #:custodian (runtime-custodian rt)))]
                [else (invoke-handler)]))
            (if (tool-descriptor-workflow d)
                (workflow-executable-fingerprint (tool-descriptor-workflow d) (current-workflow-adapters)) "render/1"))))
  (unless (and (hash? result)
               (or (and (or task? (task-handler? (tool-descriptor-handler d)))
                        (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)
                        (equal? (hash-ref result 'resultType #f) "task"))
                   (and (equal? (hash-ref result 'resultType #f) "complete") (list? (hash-ref result 'content #f)))
                   (and (equal? (hash-ref result 'resultType #f) "input_required")
                        (string? (hash-ref result 'requestState #f)) (hash? (hash-ref result 'inputRequests #f)))))
    (mcp-error -32603 "Handler returned an invalid tool result"))
  (when (equal? (hash-ref result 'resultType) "complete")
    (set! result (embedded-json (hash-set result 'content (expand-content-items (hash-ref result 'content))))))
  (when (equal? (hash-ref result 'resultType) "complete")
    (validate-complete-tool-result result (tool-descriptor-output-schema d))) result
)
