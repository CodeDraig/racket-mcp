#lang racket/base
(require "../json.rkt" "task-context.rkt" "persistent-json.rkt" "tool-result.rkt" "../clock.rkt"
         "../storage.rkt"
         "../workflow.rkt"
         (submod "../workflow.rkt" private)
         (submod "../build.rkt" private)
         "../descriptor.rkt"
         "../subscription.rkt"
         "../error.rkt"
         "input-response.rkt"
         "failure.rkt"
         "task-state.rkt"
         "task-time.rkt")
(provide start-workflow-task update-task! cancel-task! resume-task!)
(define (resume-task! workflow store id principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)] #:authorize [authorize void] #:wait? [wait? #t]
                      #:output-schema [output-schema missing])
  (resume-task/core workflow store id principal adapters custodian authorize wait? (break-enabled) output-schema))
(define (resume-task/core workflow store id principal adapters custodian authorize wait? breaks? output-schema)
  (define instance (owned store id principal))
  (define (claim thunk)
    (let loop ()
      (or (call-with-instance-worker store id thunk)
          (and wait? (begin (sync (alarm-evt (+ (current-inexact-milliseconds) 25))) (loop))))))
  (define parent-context (current-request-context))
  (define executor (current-task-executor))
  (define failure-recoveries (make-hasheq))
  (define (cancelled?)
    (define latest (owned store id principal #:allow-expired? #t))
    (or (<= (stored-instance-expires latest) (mcp-current-seconds))
        (equal? (hash-ref (hash-ref (stored-instance-state latest) 'task) 'status) "cancelled")))
  ;; A task keeps its authorization identity, but cannot inherit the polling
  ;; request's cancellation signal, progress token, or output stream.
  (parameterize ([current-custodian custodian]
                 ;; The selected executor belongs to this worker only. Host
                 ;; code may start an independent low-level task of its own.
                 [current-task-executor #f]
                 [current-task-recovery-check (lambda (_instance) (void))]
                 [current-workflow-failure-observer
                  (lambda (program failed-store flow failure)
                    (when (and (eq? store failed-store) (equal? principal (stored-instance-principal flow)))
                      (define recovery (workflow-recovery-metadata program store flow))
                      (when (and recovery (not (hash-has-key? failure-recoveries failure)))
                        (hash-set! failure-recoveries failure recovery))))]
                 [current-workflow-adapters adapters]
                 [current-workflow-task-handoff #f]
                 [current-cancellation-event never-evt]
                 [current-output-port (current-error-port)]
                 [current-cancelled? cancelled?]
                 [current-progress-token #f]
                 [current-request-context
                  (and parent-context
                       (request-context (request-context-principal parent-context)
                                        (request-context-capabilities parent-context) #f cancelled? void))])
    (thread
     (lambda ()
      (parameterize-break breaks?
       (claim (lambda ()
       (with-handlers ([non-break-failure? (lambda (e)
                                   (change! store id principal
                                     (lambda (state task) (task-failure-state workflow store state task e (hash-ref failure-recoveries e #f))) #:allow-expired? #t))])
         (define state (stored-instance-state (owned store id principal)))
         (unless (terminal? (hash-ref state 'task))
           (authorize)
           (define result
             (if executor
                 (executor (owned store id principal))
                 (run-workflow workflow store (stored-instance-arguments instance) #:principal principal
                               #:state (hash-ref state 'workflow) #:responses (hash-ref state 'responses (hasheq)) #:adapters adapters
                               #:cancelled? cancelled?)))
           (unless (and (hash? result) (equal? (hash-ref result 'resultType #f) "input_required"))
             (validate-complete-tool-result result
               (if (missing? output-schema) (hash-ref state 'outputSchema #f) output-schema)))
           (change! store id principal
             (lambda (state task)
               (set! state (if (missing? output-schema) state (hash-set state 'outputSchema output-schema)))
               (hash-set (if (equal? (hash-ref result 'resultType) "input_required")
                             (hash-set state 'continuation (hash-ref result 'requestState)) state) 'task
                         (if (equal? (hash-ref result 'resultType) "input_required")
                             (hash-set* task 'status "input_required" 'lastUpdatedAt (timestamp) 'inputRequests (hash-ref result 'inputRequests))
                             (hash-set* (hash-remove task 'inputRequests) 'status "completed" 'lastUpdatedAt (timestamp) 'result result))))))))))))))
(define (start-workflow-task workflow store arguments principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)]
                             #:output-schema [output-schema #f]
                             #:operation-name [operation-name #f]
                             #:state [handle #f] #:responses [responses (hasheq)])
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'start-workflow-task "task creation must own its storage transaction boundaries"))
  (set! arguments (for/hasheq ([(key value) (in-hash arguments)] #:unless (missing? value)) (values key value)))
  (define (handoff flow)
    (create-workflow-task workflow store arguments principal adapters custodian operation-name flow output-schema))
  (define boundary? (ormap (lambda (stage) (eq? (workflow-stage-kind stage) 'task-boundary))
                           (workflow-descriptor-stages workflow)))
  ;; A continuation already identifies its execution. Newly advertised Tasks
  ;; support cannot discard its effects or responses and start another one.
  (if (or handle boundary?)
      (parameterize ([current-workflow-task-handoff (and boundary? (cons workflow handoff))])
        (run-workflow workflow store arguments #:principal principal #:state handle
                      #:responses responses #:adapters adapters #:cancelled? (current-cancelled?)))
      (handoff #f)))
(define (create-workflow-task workflow store arguments principal adapters custodian operation-name prepared-flow output-schema)
  (define fingerprint (workflow-executable-fingerprint workflow adapters))
  ;; User key computation runs outside the database transaction, once per call.
  (define invocation-key
    (and (not prepared-flow) (workflow-invocation-key workflow arguments)))
  (set! arguments (persistent-json arguments))
  ;; Once the handoff commits, schedule its runtime-owned worker before a request
  ;; break can escape. A process crash is recovered by the runtime startup scan.
  (define worker-breaks? (break-enabled))
  (parameterize-break #f
    (define instance
      (store-transaction store
        (lambda ()
          (define flow
            (if prepared-flow
                (load-instance store (stored-instance-handle prepared-flow))
                (create-instance! store principal (workflow-descriptor-name workflow) arguments
                                  (workflow-descriptor-version workflow) fingerprint (+ (mcp-current-seconds) 86400)
                                  (hasheq 'position 0 'values arguments 'status "working" 'effects (hasheq))
                                  #:key invocation-key)))
          (define expiry (stored-instance-expires flow))
          (when (<= expiry (mcp-current-seconds)) (mcp-error -32602 "Task preparation has expired"))
          (unless (and (equal? (stored-instance-version flow) (workflow-descriptor-version workflow))
                       (equal? (stored-instance-fingerprint flow) fingerprint))
            (raise (exn:fail:recovery "workflow code is incompatible with saved execution"
                                     (current-continuation-marks) (stored-instance-handle flow) #f)))
          (define previous (hash-ref (stored-instance-state flow) 'task-handoff #f))
          (define candidate
            (if previous
                (owned store (hash-ref previous 'taskId) principal)
                (create-instance! store principal (string-append "task:" (workflow-descriptor-name workflow)) arguments
                                  (workflow-descriptor-version workflow) fingerprint expiry (hasheq 'task (hasheq))
                                  #:key (string-append "workflow:" (stored-instance-handle flow)))))
          (cond
            [(hash-has-key? (stored-instance-state candidate) 'workflow)
             (define existing (owned store (stored-instance-handle candidate) principal))
             (unless (equal? operation-name (hash-ref (stored-instance-state existing) 'operationName #f))
               (mcp-error -32602 "Task handoff belongs to another operation"))
             existing]
            [else
             (when (and prepared-flow ((current-cancelled?)))
               (error 'start-workflow-task "execution cancelled before task handoff"))
             (define time (timestamp))
             (define task
               (hasheq 'taskId (stored-instance-handle candidate) 'status "working"
                       'createdAt time 'lastUpdatedAt time
                       'ttlMs (* 1000 (- expiry (mcp-current-seconds))) 'pollIntervalMs 100))
             (define created (hash-set task 'resultType "task"))
             (define updated
               (update-instance! store candidate
                 (hasheq 'operationName operation-name
                         'outputSchema output-schema
                         'capabilities (if (current-request-context) (request-context-capabilities (current-request-context)) (hasheq))
                         'workflow (stored-instance-handle flow) 'task task 'creation-result created)))
             ;; Prepared execution holds the workflow claim. Immediate keyed
             ;; creation may share a running MRTR workflow, so its receipt lives
             ;; only on the separately keyed task record and cannot stale a stage.
             (when prepared-flow
               (update-instance! store flow (hash-set (stored-instance-state flow) 'task-handoff created))
               (record-event! store (stored-instance-handle flow)
                              (hasheq 'kind "task-handoff" 'taskId (stored-instance-handle candidate))))
             updated]))))
    (when (equal? (hash-ref (hash-ref (stored-instance-state instance) 'task) 'status) "working")
      (resume-task/core workflow store (stored-instance-handle instance) principal
                        adapters custodian void #f worker-breaks? output-schema))
    (if prepared-flow
        (hash-ref (stored-instance-state (load-instance store (stored-instance-handle prepared-flow))) 'task-handoff)
        (hash-ref (stored-instance-state instance) 'creation-result))))
(define (update-task! workflow store id principal responses #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)]
                      #:output-schema [output-schema missing])
  ;; A view restriction must reject resumption before accepting/persisting input.
  (define fingerprint (workflow-executable-fingerprint workflow adapters))
  (define updated (store-transaction store
    (lambda ()
      (define instance (owned store id principal)) (define state (stored-instance-state instance)) (define task (hash-ref state 'task))
      (unless (equal? (hash-ref task 'status) "input_required") (mcp-error -32602 "Task is not awaiting input"))
      ;; A changed declaration rejects input before changing task state. Preserve
      ;; the existing worker failure channel for ordinary adapter/program changes.
      (define flow (load-instance store (hash-ref state 'workflow)))
      (unless (and flow (and (equal? (stored-instance-version flow) (workflow-descriptor-version workflow))
                                    (equal? (stored-instance-fingerprint flow) fingerprint)))
        (mcp-error -32603 "Task workflow build is incompatible"))
      (unless (hash? responses) (mcp-error -32602 "Input responses must be an object"))
      (define accepted
        (for/hasheq ([(key response) (in-hash responses)] #:when (hash-has-key? (hash-ref task 'inputRequests) key))
          (validate-input-response (hash-ref (hash-ref (hash-ref task 'inputRequests) key) 'params) response)
          (values key response)))
      (and (positive? (hash-count accepted))
           (update-instance! store instance (hash-set* (if (missing? output-schema) state (hash-set state 'outputSchema output-schema)) 'responses accepted 'task (hash-set* (hash-remove task 'inputRequests) 'status "working" 'lastUpdatedAt (timestamp))))))))
  (when updated
    (notify-task store updated)
    (resume-task! workflow store id principal #:adapters adapters #:custodian custodian #:output-schema output-schema))
  (hasheq 'resultType "complete"))
(define (cancel-task! store id principal)
  (change! store id principal (lambda (state task) (hash-set state 'task (hash-set* (hash-remove task 'inputRequests) 'status "cancelled" 'lastUpdatedAt (timestamp)))))
  (hasheq 'resultType "complete"))

;; Local recovery API, not a new wire method. A terminal task is never revived.
;; The old task's journal records the replacement in the same transaction that
;; persists it; retrying this API cannot create multiple tasks for one repair.
