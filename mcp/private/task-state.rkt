#lang racket/base
(require "../clock.rkt"
         "../storage.rkt"
         "../workflow.rkt"
         "../error.rkt"
         "failure.rkt"
         "task-time.rkt")
(provide current-task-notify notify-task owned get-task terminal? task-failure-state change!)
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
