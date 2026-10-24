#lang racket/base
(require "runtime-state.rkt"
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
(define (dispatch-tool-call rt params render-call)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (define d (lookup-operation (interface-descriptor-tools iface) tool-descriptor-name params 'name))
  (define args (hash-ref params 'arguments (hasheq)))
  (unless (valid? (tool-descriptor-input-schema d) args) (mcp-error -32602 "Invalid tool arguments"))
  (define bound (if (tool-descriptor-raw? d) args (bind-arguments (tool-descriptor-arguments d) args)))
  (define task? (or (eq? (tool-descriptor-execution d) 'task)
                    (and (eq? (tool-descriptor-execution d) 'task-optional)
                         (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks))))
  (when (and task? (not (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)))
    (mcp-error -32021 "Client Tasks capability is required" (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
  (when (and (tool-descriptor-workflow d)
             (ormap (lambda (s) (memq (workflow-stage-kind s) '(input input-group))) (workflow-descriptor-stages (tool-descriptor-workflow d)))
             (not (hash-has-key? caps 'elicitation))) (mcp-error -32021 "Client elicitation capability is required" (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
  (define (invoke-handler)
    (define outcome ((tool-descriptor-handler d) bound))
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
  (define result (render-call (lambda () (if task?
                     (begin (unless (runtime-store rt) (mcp-error -32603 "Task storage is not configured"))
                            (start-workflow-task (tool-descriptor-workflow d) (runtime-store rt) bound (principal-key principal)
                                                 #:state (current-workflow-state) #:responses (current-workflow-responses)
                                                 #:operation-name (tool-descriptor-name d) #:adapters (current-workflow-adapters) #:custodian (runtime-custodian rt)))
                     (invoke-handler)))
                              (if (tool-descriptor-workflow d) (workflow-executable-fingerprint (tool-descriptor-workflow d) (current-workflow-adapters)) "render/1")))
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
  (when (and (equal? (hash-ref result 'resultType) "complete") (tool-descriptor-output-schema d) (not (hash-ref result 'isError #f))
             (or (not (hash-has-key? result 'structuredContent))
                 (not (valid? (tool-descriptor-output-schema d) (hash-ref result 'structuredContent)))))
    (mcp-error -32603 "Tool output failed its declared schema")) result
)
