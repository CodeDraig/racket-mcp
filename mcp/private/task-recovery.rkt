#lang racket/base
(require "../json.rkt" "task-context.rkt" racket/list "../clock.rkt" "../storage.rkt" "../workflow.rkt" "../descriptor.rkt"
         "task-state.rkt" "task-time.rkt" "task-execution.rkt")
(provide retry-recovered-task!)
;; Local recovery API, not a new wire method. A terminal task is never revived.
;; The old task's journal records the replacement in the same transaction that
;; persists it; retrying this API cannot create multiple tasks for one repair.
(define (retry-recovered-task! workflow store id principal
                               #:output-schema [output-schema missing]
                               #:adapters [adapters (hasheq)]
                               #:custodian [custodian (current-custodian)]
                               #:authorize [authorize void])
  (define original (owned store id principal))
  (authorize)
  (define flow-id (hash-ref (stored-instance-state original) 'workflow))
  ;; Legacy parent-effect records have no explicit recovery workflow identity.
  (define recovery-id (hash-ref (hash-ref (stored-instance-state original) 'recovery (hasheq)) 'workflow flow-id))
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
      (or replacement (call-with-instance-worker store recovery-id
        (lambda ()
          ;; The runtime can inspect current resource bindings outside SQLite,
          ;; under the repaired workflow's claim. Existing receipts need no replay.
          (unless (existing-replacement) ((current-task-recovery-check) original))
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
                       (define repaired-flow (load-instance store recovery-id))
                       (unless (and repaired-flow
                                    (equal? (hash-ref recovery 'workflow flow-id) recovery-id)
                                    (equal? (stored-instance-principal repaired-flow) principal)
                                    (> (stored-instance-expires repaired-flow) (mcp-current-seconds))
                                    (equal? (stored-instance-version repaired-flow) (hash-ref recovery 'version (stored-instance-version flow)))
                                    (equal? (stored-instance-fingerprint repaired-flow) (hash-ref recovery 'fingerprint (stored-instance-fingerprint flow))))
                         (error 'retry-recovered-task! "incompatible, foreign, changed, or expired recovery workflow"))
                       (define events (instance-events store recovery-id))
                       (define repaired?
                         (and (> (stored-instance-revision repaired-flow) (hash-ref recovery 'revision))
                              (equal? (hash-ref (stored-instance-state repaired-flow) 'status) "working")
                              (for/or ([event (in-list (drop events (hash-ref recovery 'eventCount)))])
                                (and (equal? (hash-ref event 'kind #f) "recovery")
                                     (equal? (hash-ref event 'stage #f) (hash-ref recovery 'stage))
                                     (member (hash-ref event 'action #f) '("outcome" "retry"))))))
                       (unless repaired? (error 'retry-recovered-task! "record an outcome or authorize effect retry before creating a replacement task"))
                       (define expiry (min (stored-instance-expires flow) (stored-instance-expires original) (stored-instance-expires repaired-flow)))
                       (define next (create-instance! store principal (stored-instance-operation original)
                                      (stored-instance-arguments original) (stored-instance-version flow)
                                      (stored-instance-fingerprint flow) expiry (hasheq 'task (hasheq))))
                       (define time (timestamp))
                       (define updated
                         (update-instance! store next
                           (let ([seed (hasheq 'workflow flow-id 'replacesTask id
                                   'operationName (hash-ref old-state 'operationName #f)
                                   'capabilities (if (current-request-context)
                                                     (request-context-capabilities (current-request-context))
                                                     (hash-ref old-state 'capabilities (hasheq)))
                                   'outputSchema (if (missing? output-schema) (hash-ref old-state 'outputSchema #f) output-schema)
                                   'responses (hash-ref old-state 'responses (hasheq))
                                   'task (hasheq 'taskId (stored-instance-handle next) 'status "working"
                                                 'createdAt time 'lastUpdatedAt time
                                                 'ttlMs (* 1000 (- expiry (mcp-current-seconds))) 'pollIntervalMs 100))])
                             (if (hash-has-key? old-state 'continuation)
                                 (hash-set seed 'continuation (hash-ref old-state 'continuation)) seed))))
                       (record-event! store id (hasheq 'kind "task-replacement" 'taskId (stored-instance-handle updated)
                                                       'workflowRevision (stored-instance-revision flow)
                                                       'recoveryWorkflow recovery-id
                                                       'recoveryWorkflowRevision (stored-instance-revision repaired-flow)))
                       (record-event! store (stored-instance-handle updated) (hasheq 'kind "replaces-task" 'taskId id))
                       updated])))))))
    (set! replacement (existing-replacement)))
  (unless replacement
    (error 'retry-recovered-task! "workflow execution is active"))
  (resume-task! workflow store (stored-instance-handle replacement) principal
                #:adapters adapters #:custodian custodian #:authorize authorize #:wait? #f
                #:output-schema output-schema)
  (hash-set (hash-ref (stored-instance-state replacement) 'task) 'resultType "task"))
