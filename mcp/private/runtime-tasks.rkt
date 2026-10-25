#lang racket/base
(require "tool-result.rkt" "task-continuations.rkt" "task-context.rkt" "../rendering.rkt" "../presentation.rkt" (submod "../workflow.rkt" private) (submod "../build.rkt" private) "runtime-state.rkt"
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
(provide task-executor authorize-upstream-task! recover-runtime-tasks! retry-runtime-task! task-notifier dispatch-runtime-task)
(define (authorize-upstream-task! rt principal id)
  (define instance (inspect-owned-task (runtime-store rt) id principal))
  (define detail (get-task (runtime-store rt) id (principal-key principal)))
  (define tool (resolve-task-operation (interface-descriptor-tools (runtime-interface rt)) instance))
  (when (and tool (equal? (hash-ref detail 'status) "completed"))
    (validate-complete-tool-result (hash-ref detail 'result #f) (tool-descriptor-output-schema tool)))
  (when (and tool (task-handler? (tool-descriptor-handler tool)))
    (unless ((runtime-authorize rt) principal "tools/call"
             (hasheq 'name (tool-descriptor-name tool)
                     'arguments (hash-ref (hash-ref (stored-instance-arguments instance) 'params) 'arguments (hasheq))))
      (mcp-error -32001 "Upstream task operation is not authorized"))
    (define handler (tool-descriptor-handler tool))
    (when (bound-task-handler? handler)
      ((bound-task-handler-check-binding handler) (runtime-store rt) id principal))))
(define (task-executor rt dispatch)
  (lambda (instance)
    (define state (stored-instance-state instance))
    (define context (current-request-context))
    (define tool (resolve-task-operation (interface-descriptor-tools (runtime-interface rt)) instance))
    (unless tool (mcp-error -32603 "Task executable is unavailable"))
    (check-managed-task! rt instance tool (request-context-principal context) (request-context-capabilities context))
    ;; The explicit continuation resumes this execution rather than queuing a
    ;; new task. A rendering continuation may outlive the parent workflow.
    (parameterize ([current-render-capture #f] [current-task-resumption tool])
      (dispatch rt "tools/call"
        (hasheq '_meta (request-meta #:capabilities (request-context-capabilities context))
                'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance)
                'requestState (hash-ref state 'continuation (hash-ref state 'workflow))
                'inputResponses (hash-ref state 'responses (hasheq)))
        #:principal (request-context-principal context)))))
;; Resolve persisted identity through application policy; credentials are never
;; serialized. Each worker reauthorizes after acquiring its instance lock.
(define/clock (recover-runtime-tasks! rt #:dispatch dispatch #:restore-principal [restore-principal values])
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
        (parameterize ([current-task-executor (task-executor rt dispatch)]
                       [current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                       [current-task-notify (task-notifier rt)])
        (resume-task! (tool-descriptor-workflow tool) store (stored-instance-handle instance) identity
                      #:output-schema (tool-descriptor-output-schema tool)
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
        (with-handlers ([(lambda (_) #t) (lambda (_) #f)])
          (and (or (not (verified-principal? reader)) (> (verified-principal-expiry reader) (mcp-current-seconds)))
               (begin (authorize-upstream-task! rt reader (hash-ref task 'taskId)) #t)
               ((runtime-authorize rt) reader "tasks/get" (hasheq 'taskId (hash-ref task 'taskId)))))))))
(define (task-recovery-render-path store instance repaired)
  (define state (stored-instance-state instance))
  (define principal (stored-instance-principal instance))
  (define token (hash-ref state 'continuation #f))
  (define root
    (if (render-continuation? store token) (load-instance store token)
        (find-instance-by-key store principal "render:tools/call"
          (string-append "workflow-render:" (hash-ref state 'workflow)))))
  (define (visit render depth)
    (and render (< depth 32)
      (for/or ([child (in-list (hash-ref (stored-instance-state render) 'children))]
               #:unless (equal? (hash-ref child 'status) "complete"))
        (define key (format "~a/~a" (stored-instance-handle render) (hash-ref child '$mcp/embedding)))
        (define flow (find-instance-by-key store principal (stored-instance-operation repaired) key))
        (cond [(and flow (equal? (stored-instance-handle flow) (stored-instance-handle repaired)))
               (list (cons (hash-ref child 'uri) #f))]
              [else
               (define child-state (hash-ref child 'state #f))
               (define nested
                 (if (render-continuation? store child-state) (load-instance store child-state)
                     (find-instance-by-key store principal "render:resources/read" key)))
               (define rest (visit nested (add1 depth)))
               (and rest (cons (cons (hash-ref child 'uri) nested) rest))]))))
  (or (visit root 0) (mcp-error -32602 "Recovery workflow has no matching embedded resource binding")))
(define (check-task-recovery-binding! rt instance tool principal caps)
  (define store (runtime-store rt))
  (define state (stored-instance-state instance))
  (define flow-id (hash-ref state 'workflow))
  (define recovery-id (hash-ref (hash-ref state 'recovery (hasheq)) 'workflow flow-id))
  (unless (equal? recovery-id flow-id)
    (define repaired (or (load-instance store recovery-id) (mcp-error -32602 "Recovery workflow is absent")))
    (for/fold ([adapters (operation-adapters rt tool)])
              ([entry (in-list (task-recovery-render-path store instance repaired))])
      (define uri (car entry))
      (define render (cdr entry))
      (define params (hasheq 'uri uri '_meta (request-meta #:capabilities caps)))
      (define matches (operation-targets (runtime-interface rt) store "resources/read" params))
      (unless (= (length matches) 1) (mcp-error -32602 "Recovery resource binding is absent or ambiguous"))
      (define resource (car matches))
      (define effective (parameterize ([current-workflow-adapters adapters]) (operation-adapters rt resource)))
      (define program
        (and (resource-descriptor-workflow resource)
          (workflow-add-fingerprint-suffix (resource-descriptor-workflow resource)
            (string-append ":renderer:" (renderer-fingerprint (resource-descriptor-renderer resource))))))
      (define fingerprint
        (if program (workflow-executable-fingerprint program effective)
            (string-append "render/1:renderer:" (renderer-fingerprint (resource-descriptor-renderer resource)))))
      (unless (if render
                  (and (equal? (stored-instance-version render) "render/3")
                       (equal? (stored-instance-fingerprint render) (bind-build-identity fingerprint)))
                  (and program
                       (equal? (stored-instance-operation repaired) (string-append "resources/read:" (workflow-descriptor-name program)))
                       (equal? (stored-instance-version repaired) (workflow-descriptor-version program))
                       (equal? (stored-instance-fingerprint repaired) fingerprint)))
        (mcp-error -32602 "Recovery resource executable is incompatible"))
      (unless ((runtime-authorize rt) principal "resources/read" params)
        (mcp-error -32001 "Recovery resource is not authorized"))
      (when (and program (not (hash-has-key? caps 'elicitation))
                 (ormap (lambda (stage) (memq (workflow-stage-kind stage) '(input input-group)))
                        (workflow-descriptor-stages program)))
        (mcp-error -32021 "Client elicitation capability is required"
          (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
      effective)))
;; An explicit local action after recovery, never an automatic wire retry.
(define/clock (retry-runtime-task! rt id #:dispatch dispatch #:principal principal #:capabilities supplied-caps)
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
  (when (and (or (ormap (lambda (stage) (memq (workflow-stage-kind stage) '(input input-group)))
                        (workflow-descriptor-stages (tool-descriptor-workflow tool)))
                 (hash-ref (hash-ref (stored-instance-state instance) 'recovery (hasheq)) 'requiresElicitation #f))
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
                 [current-task-executor (task-executor rt dispatch)]
                 [current-task-recovery-check
                  (lambda (original)
                    (check-managed-task! rt original tool principal caps)
                    (check-task-recovery-binding! rt original tool principal caps))]
                 [current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                 [current-task-notify (task-notifier rt)])
    (retry-recovered-task! (tool-descriptor-workflow tool) store id identity
      #:output-schema (tool-descriptor-output-schema tool)
      #:adapters (operation-adapters rt tool) #:custodian (runtime-custodian rt) #:authorize authorize)))

(define (dispatch-runtime-task rt method params executor)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (unless (runtime-store rt) (mcp-error -32601 "Tasks are not configured"))
  (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks) (mcp-error -32021 "Client Tasks capability is required"
    (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
  (define task-id (hash-ref params 'taskId #f))
  (unless (string? task-id) (mcp-error -32602 "taskId must be a string"))
  (define task-instance (inspect-owned-task (runtime-store rt) task-id principal))
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
    [(tasks/get)
     (define detail (get-task (runtime-store rt) task-id (principal-key principal)))
     (when (and task-tool (equal? (hash-ref detail 'status) "completed"))
       (validate-complete-tool-result (hash-ref detail 'result #f) (tool-descriptor-output-schema task-tool)))
     detail]
    [(tasks/cancel) (cancel-task! (runtime-store rt) task-id (principal-key principal))]
    [(tasks/update)
     (define instance (load-instance (runtime-store rt) task-id))
     (unless instance (mcp-error -32602 "Unknown task"))
     (define tool (resolve-task-operation (interface-descriptor-tools iface) instance))
     (unless tool (mcp-error -32603 "Task executable is unavailable"))
     (unless ((runtime-authorize rt) principal "tools/call" (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance)))
       (mcp-error -32001 "Resumed operation is not authorized"))
     (check-managed-task! rt instance tool principal caps)
     (parameterize ([current-task-executor executor])
     (update-task! (tool-descriptor-workflow tool) (runtime-store rt) task-id (principal-key principal) (hash-ref params 'inputResponses (hasheq)) #:adapters (current-workflow-adapters) #:custodian (runtime-custodian rt) #:output-schema (tool-descriptor-output-schema tool)))]))
)
