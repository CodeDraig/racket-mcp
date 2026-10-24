#lang racket/base
(require "runtime-state.rkt"
         "runtime-policy.rkt"
         "runtime-changes.rkt"
         "request-meta.rkt"
         "handler-info.rkt"
         "task-observation.rkt"
         "../clock.rkt"
         "../json.rkt"
         "../descriptor.rkt"
         "../workflow.rkt"
         "../storage.rkt"
         "../tasks.rkt"
         "../subscription.rkt"
         "../authorization.rkt"
         "../error.rkt")
(provide recover-runtime-tasks! retry-runtime-task! task-notifier dispatch-runtime-task)
;; Resolve persisted identity through application policy; credentials are never
;; serialized. Each worker reauthorizes after acquiring its instance lock.
(define/clock (recover-runtime-tasks! rt #:restore-principal [restore-principal values])
  (define store (runtime-store rt))
  (if (not store) '()
      (for/list ([instance (in-list (list-instances store))]
                 #:when (and (not (equal? (hash-ref (stored-instance-state instance) 'kind #f) "upstream-task"))
                             (> (stored-instance-expires instance) (mcp-current-seconds))
                             (equal? (hash-ref (hash-ref (stored-instance-state instance) 'task (hasheq)) 'status #f) "working")))
        (define tool
          (resolve-task-operation (interface-descriptor-tools (runtime-interface rt)) instance))
        (unless tool (error 'recover-runtime-tasks! "no executable for persisted task ~a" (stored-instance-operation instance)))
        (define identity (stored-instance-principal instance))
        (parameterize ([current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                       [current-task-notify (task-notifier rt)])
        (resume-task! (tool-descriptor-workflow tool) store (stored-instance-handle instance) identity
                      #:adapters (operation-adapters rt tool) #:custodian (runtime-custodian rt) #:wait? #f
                      #:authorize
                      (lambda ()
                        (define principal (restore-principal identity))
                        (unless (and principal (equal? (principal-key principal) identity)
                                     (or (not (verified-principal? principal))
                                         (> (verified-principal-expiry principal) (mcp-current-seconds)))
                                     ((runtime-authorize rt) principal "tools/call"
                                      (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance))))
                          (error 'recover-runtime-tasks! "task principal is no longer authorized"))
                        (current-request-context
                         (request-context principal (hash-ref (stored-instance-state instance) 'capabilities (hasheq))
                                          #f (current-cancelled?) void))))))))
(define (task-notifier rt)
  (lambda (principal task)
    (publish-change! (runtime-subscriptions rt) "notifications/tasks" task
                     #:principal principal #:principal-key principal-key
                     #:authorized? (lambda (reader)
                       (and (or (not (verified-principal? reader)) (> (verified-principal-expiry reader) (mcp-current-seconds)))
                            ((runtime-authorize rt) reader "tasks/get" (hasheq 'taskId (hash-ref task 'taskId))))))))
;; An explicit local action after recovery, never an automatic wire retry.
(define/clock (retry-runtime-task! rt id #:principal principal #:capabilities supplied-caps)
  (define caps (string->json (json->string supplied-caps)))
  (define store (runtime-store rt))
  (unless store (mcp-error -32601 "Tasks are not configured"))
  (validate-request-meta (hasheq '_meta (request-meta #:capabilities caps)))
  (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)
    (mcp-error -32021 "Client Tasks capability is required"
      (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
  (define identity (principal-key principal))
  (get-task store id identity)
  (define instance (load-instance store id))
  (define tool (resolve-task-operation (interface-descriptor-tools (runtime-interface rt)) instance))
  (unless tool (mcp-error -32001 "Task operation is absent from this interface"))
  (unless (tool-descriptor-workflow tool)
    (mcp-error -32602 "Upstream task recovery requires a separately observed upstream outcome"))
  (when (and (ormap (lambda (stage) (memq (workflow-stage-kind stage) '(input input-group)))
                    (workflow-descriptor-stages (tool-descriptor-workflow tool)))
             (not (hash-has-key? caps 'elicitation)))
    (mcp-error -32021 "Client elicitation capability is required"
      (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
  (define (authorize)
    (unless (and (or (not (verified-principal? principal)) (> (verified-principal-expiry principal) (mcp-current-seconds)))
                 ((runtime-authorize rt) principal "tasks/get" (hasheq 'taskId id))
                 ((runtime-authorize rt) principal "tools/call"
                   (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance))))
      (mcp-error -32001 "Repaired task execution is not authorized"))
    (current-request-context (request-context principal caps #f (current-cancelled?) void)))
  (parameterize ([current-request-context #f]
                 [current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                 [current-task-notify (task-notifier rt)])
    (retry-recovered-task! (tool-descriptor-workflow tool) store id identity
      #:adapters (operation-adapters rt tool) #:custodian (runtime-custodian rt) #:authorize authorize)))
(define (dispatch-runtime-task rt method params)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (unless (runtime-store rt) (mcp-error -32601 "Tasks are not configured"))
  (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks) (mcp-error -32021 "Client Tasks capability is required"
    (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
  (define task-id (hash-ref params 'taskId #f))
  (unless (string? task-id) (mcp-error -32602 "taskId must be a string"))
  (define task-instance (load-instance (runtime-store rt) task-id))
  (define task-tool (and task-instance (resolve-task-operation (interface-descriptor-tools iface) task-instance)))
  (when (and (current-upstream-task-observation)
             (equal? task-id (car (current-upstream-task-observation)))
             (not (and task-tool (task-handler? (tool-descriptor-handler task-tool)))))
    (mcp-error -32602 "Task does not have an upstream observation handler"))
  (if (and task-tool (task-handler? (tool-descriptor-handler task-tool)))
      (begin
        ;; Validate ownership before authorization callbacks or upstream I/O.
        (get-task (runtime-store rt) task-id (principal-key principal))
        (unless ((runtime-authorize rt) principal "tools/call"
                 (hasheq 'name (tool-descriptor-name task-tool)
                         'arguments (hash-ref (hash-ref (stored-instance-arguments task-instance) 'params) 'arguments (hasheq))))
          (mcp-error -32001 "Upstream task operation is not authorized"))
        ((task-handler-dispatch (tool-descriptor-handler task-tool)) method task-id params))
  (case (string->symbol method)
    [(tasks/get) (get-task (runtime-store rt) task-id (principal-key principal))]
    [(tasks/cancel) (cancel-task! (runtime-store rt) task-id (principal-key principal))]
    [(tasks/update)
     (define instance (load-instance (runtime-store rt) task-id))
     (unless instance (mcp-error -32602 "Unknown task"))
     (define tool (resolve-task-operation (interface-descriptor-tools iface) instance))
     (unless tool (mcp-error -32603 "Task executable is unavailable"))
     (unless ((runtime-authorize rt) principal "tools/call" (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance)))
       (mcp-error -32001 "Resumed operation is not authorized"))
     (update-task! (tool-descriptor-workflow tool) (runtime-store rt) task-id (principal-key principal) (hash-ref params 'inputResponses (hasheq)) #:adapters (current-workflow-adapters) #:custodian (runtime-custodian rt))]))
)
