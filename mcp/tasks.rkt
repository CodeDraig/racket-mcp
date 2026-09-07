#lang racket/base
(require "clock.rkt" racket/list "private/failure.rkt" (submod "workflow.rkt" private))
(require racket/date racket/format "storage.rkt" "workflow.rkt" "json.rkt" "descriptor.rkt" "subscription.rkt" "error.rkt" "private/input-response.rkt")
(provide start-workflow-task get-task update-task! cancel-task! resume-task! retry-recovered-task! current-task-notify)
;; Called only after a committed task transition, with its owner key and detail.
(define current-task-notify (make-parameter (lambda (principal task) (void))))
(define (notify-task store instance)
  (when (stored-instance? instance)
    (with-handlers ([non-break-failure? (lambda (e) (eprintf "Task notification delivery failed: ~a\n" (failure-message e)))])
      (store-transaction store
        (lambda ()
          ;; If another transition won before publication, omit this obsolete
          ;; hint. Hold the read transaction through enqueueing so a later
          ;; transition cannot publish ahead of this one.
          (define current (load-instance store (stored-instance-handle instance)))
          (when (= (stored-instance-revision current) (stored-instance-revision instance))
            ((current-task-notify) (stored-instance-principal instance) (hash-ref (stored-instance-state instance) 'task))))))))
(define (timestamp)
  (define d (seconds->date (mcp-current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~aZ" (~r (date-year d) #:min-width 4 #:pad-string "0")
          (~r (date-month d) #:min-width 2 #:pad-string "0") (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0") (~r (date-minute d) #:min-width 2 #:pad-string "0") (~r (date-second d) #:min-width 2 #:pad-string "0")))
(define (owned store id principal)
  (define instance (or (load-instance store id) (mcp-error -32602 "Unknown task")))
  (unless (and (equal? (stored-instance-principal instance) principal) (hash-has-key? (stored-instance-state instance) 'task)) (mcp-error -32602 "Unknown or foreign task"))
  (when (<= (stored-instance-expires instance) (mcp-current-seconds)) (mcp-error -32602 "Task has expired")) instance)
(define (get-task store id principal)
  (hash-set (hash-ref (stored-instance-state (owned store id principal)) 'task) 'resultType "complete"))
(define (terminal? task) (member (hash-ref task 'status) '("completed" "failed" "cancelled")))
(define (task-failure-state workflow store state task failure)
  (define flow (load-instance store (hash-ref state 'workflow)))
  (define position (hash-ref (stored-instance-state flow) 'position))
  (define stages (workflow-descriptor-stages workflow))
  (define stage (and (< position (length stages)) (list-ref stages position)))
  (define intent (and stage (hash-ref (hash-ref (stored-instance-state flow) 'effects) (workflow-stage-id stage) #f)))
  (define uncertain?
    (and stage (eq? (workflow-stage-kind stage) 'effect) (eq? (workflow-stage-policy stage) 'manual)
         intent (= (hash-ref intent 'position) position) (equal? (hash-ref intent 'status) "intent")))
  (define failed
    (hash-set state 'task (hash-set* task 'status "failed" 'lastUpdatedAt (timestamp)
      'error (hasheq 'code -32603 'message (if (or uncertain? (exn:fail:recovery? failure)) "Workflow requires manual recovery" "Task execution failed")))))
  (if uncertain?
      (hash-set failed 'recovery
        (hasheq 'stage (symbol->string (workflow-stage-id stage)) 'revision (stored-instance-revision flow)
                'eventCount (length (instance-events store (stored-instance-handle flow)))))
      failed))
(define (change! store id principal transform)
  (define updated
    (store-transaction store (lambda () (define instance (owned store id principal))
                              (define state (stored-instance-state instance))
                              (define task (hash-ref state 'task))
                              (unless (terminal? task) (update-instance! store instance (transform state task))))))
  (notify-task store updated))
(define (resume-task! workflow store id principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)] #:authorize [authorize void] #:wait? [wait? #t])
  (resume-task/core workflow store id principal adapters custodian authorize wait? (break-enabled)))
(define (resume-task/core workflow store id principal adapters custodian authorize wait? breaks?)
  (define instance (owned store id principal))
  (define (claim thunk)
    (let loop ()
      (or (call-with-instance-worker store id thunk)
          (and wait? (begin (sync (alarm-evt (+ (current-inexact-milliseconds) 25))) (loop))))))
  (define parent-context (current-request-context))
  (define (cancelled?) (equal? (hash-ref (get-task store id principal) 'status) "cancelled"))
  ;; A task keeps its authorization identity, but cannot inherit the polling
  ;; request's cancellation signal, progress token, or output stream.
  (parameterize ([current-custodian custodian]
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
                                     (lambda (state task) (task-failure-state workflow store state task e))))])
         (define state (stored-instance-state (owned store id principal)))
         (unless (terminal? (hash-ref state 'task))
           (authorize)
           (define result (run-workflow workflow store (stored-instance-arguments instance) #:principal principal
                                        #:state (hash-ref state 'workflow) #:responses (hash-ref state 'responses (hasheq)) #:adapters adapters
                                        #:cancelled? cancelled?))
           (change! store id principal
             (lambda (state task)
               (hash-set state 'task
                         (if (equal? (hash-ref result 'resultType) "input_required")
                             (hash-set* task 'status "input_required" 'lastUpdatedAt (timestamp) 'inputRequests (hash-ref result 'inputRequests))
                             (hash-set* (hash-remove task 'inputRequests) 'status "completed" 'lastUpdatedAt (timestamp) 'result result))))))))))))))
(define (start-workflow-task workflow store arguments principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)]
                             #:operation-name [operation-name #f]
                             #:state [handle #f] #:responses [responses (hasheq)])
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'start-workflow-task "task creation must own its storage transaction boundaries"))
  (define (handoff flow)
    (create-workflow-task workflow store arguments principal adapters custodian operation-name flow))
  (if (ormap (lambda (stage) (eq? (workflow-stage-kind stage) 'task-boundary))
             (workflow-descriptor-stages workflow))
      (parameterize ([current-workflow-task-handoff (cons workflow handoff)])
        (run-workflow workflow store arguments #:principal principal #:state handle
                      #:responses responses #:adapters adapters #:cancelled? (current-cancelled?)))
      (handoff #f)))
(define (create-workflow-task workflow store arguments principal adapters custodian operation-name prepared-flow)
  (define fingerprint (workflow-executable-fingerprint workflow adapters))
  ;; User key computation runs outside the database transaction, once per call.
  (define invocation-key
    (and (not prepared-flow) (workflow-invocation-key workflow arguments)))
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
                        adapters custodian void #f worker-breaks?))
    (if prepared-flow
        (hash-ref (stored-instance-state (load-instance store (stored-instance-handle prepared-flow))) 'task-handoff)
        (hash-ref (stored-instance-state instance) 'creation-result))))
(define (update-task! workflow store id principal responses #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)])
  ;; A view restriction must reject resumption before accepting/persisting input.
  (void (workflow-executable-fingerprint workflow adapters))
  (define updated (store-transaction store
    (lambda ()
      (define instance (owned store id principal)) (define state (stored-instance-state instance)) (define task (hash-ref state 'task))
      (unless (equal? (hash-ref task 'status) "input_required") (mcp-error -32602 "Task is not awaiting input"))
      (unless (hash? responses) (mcp-error -32602 "Input responses must be an object"))
      (define accepted
        (for/hasheq ([(key response) (in-hash responses)] #:when (hash-has-key? (hash-ref task 'inputRequests) key))
          (validate-input-response (hash-ref (hash-ref (hash-ref task 'inputRequests) key) 'params) response)
          (values key response)))
      (and (positive? (hash-count accepted))
           (update-instance! store instance (hash-set* state 'responses accepted 'task (hash-set* (hash-remove task 'inputRequests) 'status "working" 'lastUpdatedAt (timestamp))))))))
  (when updated
    (notify-task store updated)
    (resume-task! workflow store id principal #:adapters adapters #:custodian custodian))
  (hasheq 'resultType "complete"))
(define (cancel-task! store id principal)
  (change! store id principal (lambda (state task) (hash-set state 'task (hash-set* (hash-remove task 'inputRequests) 'status "cancelled" 'lastUpdatedAt (timestamp)))))
  (hasheq 'resultType "complete"))

;; Local recovery API, not a new wire method. A terminal task is never revived.
;; The old task's journal records the replacement in the same transaction that
;; persists it; retrying this API cannot create multiple tasks for one repair.
(define (retry-recovered-task! workflow store id principal
                               #:adapters [adapters (hasheq)]
                               #:custodian [custodian (current-custodian)]
                               #:authorize [authorize void])
  (authorize)
  (define original (owned store id principal))
  (define flow-id (hash-ref (stored-instance-state original) 'workflow))
  (define (check-executable! flow original)
    (unless (and flow (equal? (stored-instance-principal flow) principal)
                 (equal? (stored-instance-arguments flow) (stored-instance-arguments original))
                 (equal? (stored-instance-operation flow) (workflow-descriptor-name workflow))
                 (equal? (stored-instance-version flow) (workflow-descriptor-version workflow))
                 (equal? (stored-instance-fingerprint flow) (workflow-executable-fingerprint workflow adapters))
                 (> (stored-instance-expires flow) (mcp-current-seconds)))
      (error 'retry-recovered-task! "incompatible, foreign, changed, or expired workflow")))
  (check-executable! (load-instance store flow-id) original)
  (define (existing-replacement)
    (store-transaction store
      (lambda ()
        (owned store id principal)
        (define event (findf (lambda (event) (equal? (hash-ref event 'kind #f) "task-replacement")) (instance-events store id)))
        (and event (owned store (hash-ref event 'taskId) principal)))))
  (define replacement (existing-replacement))
  (unless
      (or replacement (call-with-instance-worker store flow-id
        (lambda ()
          (set! replacement
            (store-transaction store
              (lambda ()
                (define original (owned store id principal))
                (define old-state (stored-instance-state original))
                (unless (and (equal? (hash-ref (hash-ref old-state 'task) 'status) "failed")
                             (hash-has-key? old-state 'recovery))
                  (error 'retry-recovered-task! "task did not fail with a recoverable uncertain effect"))
                (define flow (or (load-instance store flow-id) (error 'retry-recovered-task! "workflow is absent")))
                (check-executable! flow original)
                (define existing
                  (findf (lambda (event) (equal? (hash-ref event 'kind #f) "task-replacement")) (instance-events store id)))
                (cond [existing (owned store (hash-ref existing 'taskId) principal)]
                      [else
                       (define recovery (hash-ref old-state 'recovery))
                       (define events (instance-events store flow-id))
                       (define repaired?
                         (and (> (stored-instance-revision flow) (hash-ref recovery 'revision))
                              (equal? (hash-ref (stored-instance-state flow) 'status) "working")
                              (for/or ([event (in-list (drop events (hash-ref recovery 'eventCount)))])
                                (and (equal? (hash-ref event 'kind #f) "recovery")
                                     (equal? (hash-ref event 'stage #f) (hash-ref recovery 'stage))
                                     (member (hash-ref event 'action #f) '("outcome" "retry"))))))
                       (unless repaired? (error 'retry-recovered-task! "record an outcome or authorize effect retry before creating a replacement task"))
                       (define expiry (min (stored-instance-expires flow) (stored-instance-expires original)))
                       (define next (create-instance! store principal (stored-instance-operation original)
                                      (stored-instance-arguments original) (stored-instance-version flow)
                                      (stored-instance-fingerprint flow) expiry (hasheq 'task (hasheq))))
                       (define time (timestamp))
                       (define updated
                         (update-instance! store next
                           (hasheq 'workflow flow-id 'replacesTask id
                                   'operationName (hash-ref old-state 'operationName #f)
                                   'capabilities (if (current-request-context)
                                                     (request-context-capabilities (current-request-context))
                                                     (hash-ref old-state 'capabilities (hasheq)))
                                   'responses (hash-ref old-state 'responses (hasheq))
                                   'task (hasheq 'taskId (stored-instance-handle next) 'status "working"
                                                 'createdAt time 'lastUpdatedAt time
                                                 'ttlMs (* 1000 (- expiry (mcp-current-seconds))) 'pollIntervalMs 100))))
                       (record-event! store id (hasheq 'kind "task-replacement" 'taskId (stored-instance-handle updated)
                                                       'workflowRevision (stored-instance-revision flow)))
                       (record-event! store (stored-instance-handle updated) (hasheq 'kind "replaces-task" 'taskId id))
                       updated])))))))
    (set! replacement (existing-replacement)))
  (unless replacement
    (error 'retry-recovered-task! "workflow execution is active"))
  (resume-task! workflow store (stored-instance-handle replacement) principal
                #:adapters adapters #:custodian custodian #:authorize authorize #:wait? #f)
  (hash-set (hash-ref (stored-instance-state replacement) 'task) 'resultType "task"))
