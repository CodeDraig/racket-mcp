#lang racket/base
(require racket/date racket/format "storage.rkt" "workflow.rkt" "json.rkt" "descriptor.rkt" "subscription.rkt" "error.rkt" "private/input-response.rkt")
(provide start-workflow-task get-task update-task! cancel-task! resume-task! current-task-notify)
;; Called only after a committed task transition, with its owner key and detail.
(define current-task-notify (make-parameter (lambda (principal task) (void))))
(define (notify-task store instance)
  (when (stored-instance? instance)
    (with-handlers ([exn:fail? (lambda (e) (eprintf "Task notification delivery failed: ~a\n" (exn-message e)))])
      (store-transaction store
        (lambda ()
          ;; If another transition won before publication, omit this obsolete
          ;; hint. Hold the read transaction through enqueueing so a later
          ;; transition cannot publish ahead of this one.
          (define current (load-instance store (stored-instance-handle instance)))
          (when (= (stored-instance-revision current) (stored-instance-revision instance))
            ((current-task-notify) (stored-instance-principal instance) (hash-ref (stored-instance-state instance) 'task))))))))
(define (timestamp)
  (define d (seconds->date (current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~aZ" (~r (date-year d) #:min-width 4 #:pad-string "0")
          (~r (date-month d) #:min-width 2 #:pad-string "0") (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0") (~r (date-minute d) #:min-width 2 #:pad-string "0") (~r (date-second d) #:min-width 2 #:pad-string "0")))
(define (owned store id principal)
  (define instance (or (load-instance store id) (mcp-error -32602 "Unknown task")))
  (unless (and (equal? (stored-instance-principal instance) principal) (hash-has-key? (stored-instance-state instance) 'task)) (mcp-error -32602 "Unknown or foreign task"))
  (when (<= (stored-instance-expires instance) (current-seconds)) (mcp-error -32602 "Task has expired")) instance)
(define (get-task store id principal)
  (hash-set (hash-ref (stored-instance-state (owned store id principal)) 'task) 'resultType "complete"))
(define (terminal? task) (member (hash-ref task 'status) '("completed" "failed" "cancelled")))
(define (change! store id principal transform)
  (define updated
    (store-transaction store (lambda () (define instance (owned store id principal))
                              (define state (stored-instance-state instance))
                              (define task (hash-ref state 'task))
                              (unless (terminal? task) (update-instance! store instance (transform state task))))))
  (notify-task store updated))
(define (resume-task! workflow store id principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)] #:authorize [authorize void] #:wait? [wait? #t])
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
       (claim (lambda ()
       (with-handlers ([exn:fail? (lambda (e)
                                   (change! store id principal
                                     (lambda (state task) (hash-set state 'task (hash-set* task 'status "failed" 'lastUpdatedAt (timestamp)
                                                                                        'error (hasheq 'code -32603 'message (if (exn:fail:recovery? e) "Workflow requires manual recovery" "Task execution failed")))))))])
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
                             (hash-set* (hash-remove task 'inputRequests) 'status "completed" 'lastUpdatedAt (timestamp) 'result result)))))))))))))
(define (start-workflow-task workflow store arguments principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)]
                             #:operation-name [operation-name #f])
  (define expiry (+ (current-seconds) 86400))
  (define instance
    (store-transaction store
      (lambda ()
        (define flow (create-instance! store principal (workflow-descriptor-name workflow) arguments (workflow-descriptor-version workflow) (workflow-executable-fingerprint workflow adapters) expiry
                                       (hasheq 'position 0 'values arguments 'status "working" 'effects (hasheq))))
        (define instance (create-instance! store principal (string-append "task:" (workflow-descriptor-name workflow)) arguments
                                           (workflow-descriptor-version workflow) (workflow-executable-fingerprint workflow adapters) expiry (hasheq 'task (hasheq))))
        (define time (timestamp))
        (update-instance! store instance (hasheq 'operationName operation-name 'capabilities (if (current-request-context) (request-context-capabilities (current-request-context)) (hasheq))
                                                 'workflow (stored-instance-handle flow)
                                                 'task (hasheq 'taskId (stored-instance-handle instance) 'status "working" 'createdAt time 'lastUpdatedAt time 'ttlMs 86400000 'pollIntervalMs 100))))))
  (resume-task! workflow store (stored-instance-handle instance) principal #:adapters adapters #:custodian custodian)
  (hash-set (hash-ref (stored-instance-state instance) 'task) 'resultType "task"))
(define (update-task! workflow store id principal responses #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)])
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
