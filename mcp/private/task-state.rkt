#lang racket/base
(require "tool-result.rkt" "../clock.rkt"
         "../storage.rkt"
         "../workflow.rkt"
         "../error.rkt"
         "failure.rkt"
         "task-time.rkt")
(provide current-task-notify notify-task owned get-task terminal? task-failure-state workflow-recovery-metadata change!)
;; Called only after a committed task transition, with its owner key and detail.
(define current-task-notify (make-parameter (lambda (principal task) (void))))
(define (notify-task store instance)
  (when (stored-instance? instance)
    (with-handlers ([non-break-failure? (lambda (e) (eprintf "Task notification delivery failed (notification/failure)\n"))])
      (store-transaction store
        (lambda ()
          ;; If another transition won before publication, omit this obsolete
          ;; hint. Hold the read transaction through enqueueing so a later
          ;; transition cannot publish ahead of this one.
          (define current (load-instance store (stored-instance-handle instance)))
          (when (= (stored-instance-revision current) (stored-instance-revision instance))
            ((current-task-notify) (stored-instance-principal instance) (validated-task (stored-instance-state instance)))))))))
(define (owned store id principal #:allow-expired? [allow-expired? #f])
  (define instance (or (load-instance store id) (mcp-error -32602 "Unknown task")))
  (unless (and (equal? (stored-instance-principal instance) principal) (hash-has-key? (stored-instance-state instance) 'task)) (mcp-error -32602 "Unknown or foreign task"))
  (when (and (not allow-expired?) (<= (stored-instance-expires instance) (mcp-current-seconds))) (mcp-error -32602 "Task has expired")) instance)
(define (validated-task state)
  (define task (hash-ref state 'task))
  (when (equal? (hash-ref task 'status) "completed")
    (validate-complete-tool-result (hash-ref task 'result #f) (hash-ref state 'outputSchema #f)))
  task)
(define (get-task store id principal)
  (hash-set (validated-task (stored-instance-state (owned store id principal))) 'resultType "complete"))
(define (terminal? task) (member (hash-ref task 'status) '("completed" "failed" "cancelled")))
(define (workflow-recovery-metadata workflow store flow)
  ;; A restricted adapter map can reject fingerprint lookup itself. Failure
  ;; bookkeeping must still finish, without inventing uncertain-effect evidence.
  (define compatible?
    (with-handlers ([non-break-failure? (lambda (_) #f)])
      (and flow
           (equal? (stored-instance-version flow) (workflow-descriptor-version workflow))
           (equal? (stored-instance-fingerprint flow)
                   (workflow-executable-fingerprint workflow (current-workflow-adapters))))))
  (define position (and flow (hash-ref (stored-instance-state flow) 'position #f)))
  (define stages (workflow-descriptor-stages workflow))
  (define stage (and position (< position (length stages)) (list-ref stages position)))
  (define intent (and stage (hash-ref (hash-ref (stored-instance-state flow) 'effects) (workflow-stage-id stage) #f)))
  (and compatible? stage (eq? (workflow-stage-kind stage) 'effect) (eq? (workflow-stage-policy stage) 'manual)
       intent (= (hash-ref intent 'position) position) (equal? (hash-ref intent 'status) "intent")
       (hasheq 'workflow (stored-instance-handle flow)
               'version (stored-instance-version flow) 'fingerprint (stored-instance-fingerprint flow)
               'requiresElicitation (ormap (lambda (stage) (and (memq (workflow-stage-kind stage) '(input input-group)) #t))
                                           (workflow-descriptor-stages workflow))
               'stage (symbol->string (workflow-stage-id stage)) 'revision (stored-instance-revision flow)
               'eventCount (length (instance-events store (stored-instance-handle flow))))))
(define (task-failure-state workflow store state task failure observed)
  (define recovery
    (or observed (workflow-recovery-metadata workflow store (load-instance store (hash-ref state 'workflow)))))
  (define failed
    (hash-set state 'task (hash-set* task 'status "failed" 'lastUpdatedAt (timestamp)
      'error (hasheq 'code -32603 'message (cond [recovery "Workflow requires manual recovery"] [(exn:fail:recovery? failure) "Task executable is incompatible with saved execution"] [else "Task execution failed"])))))
  (if recovery (hash-set failed 'recovery recovery) failed))
(define (change! store id principal transform #:allow-expired? [allow-expired? #f])
  (define updated
    (store-transaction store (lambda () (define instance (owned store id principal #:allow-expired? allow-expired?))
                              (define state (stored-instance-state instance))
                              (define task (hash-ref state 'task))
                              (unless (terminal? task) (update-instance! store instance (transform state task))))))
  (notify-task store updated))
