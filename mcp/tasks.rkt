#lang racket/base
(require racket/date racket/format "storage.rkt" "workflow.rkt" "json.rkt" "descriptor.rkt" "subscription.rkt")
(provide start-workflow-task get-task update-task! cancel-task! resume-task!)
(define (timestamp)
  (define d (seconds->date (current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~aZ" (~r (date-year d) #:min-width 4 #:pad-string "0")
          (~r (date-month d) #:min-width 2 #:pad-string "0") (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0") (~r (date-minute d) #:min-width 2 #:pad-string "0") (~r (date-second d) #:min-width 2 #:pad-string "0")))
(define (owned store id principal)
  (define instance (or (load-instance store id) (error 'tasks "unknown task")))
  (unless (and (equal? (stored-instance-principal instance) principal) (hash-has-key? (stored-instance-state instance) 'task)) (error 'tasks "foreign task"))
  (when (<= (stored-instance-expires instance) (current-seconds)) (error 'tasks "expired task")) instance)
(define (get-task store id principal)
  (hash-set (hash-ref (stored-instance-state (owned store id principal)) 'task) 'resultType "complete"))
(define (terminal? task) (member (hash-ref task 'status) '("completed" "failed" "cancelled")))
(define (change! store id principal transform)
  (store-transaction store (lambda () (define instance (owned store id principal))
                            (define state (stored-instance-state instance))
                            (define task (hash-ref state 'task))
                            (unless (terminal? task) (update-instance! store instance (transform state task))))))
(define (resume-task! workflow store id principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)])
  (define instance (owned store id principal))
  (define parent-context (current-request-context))
  (define (cancelled?) (equal? (hash-ref (get-task store id principal) 'status) "cancelled"))
  ;; A task keeps its authorization identity, but cannot inherit the polling
  ;; request's cancellation signal, progress token, or output stream.
  (parameterize ([current-custodian custodian]
                 [current-cancellation-event never-evt]
                 [current-cancelled? cancelled?]
                 [current-progress-token #f]
                 [current-request-context
                  (and parent-context
                       (request-context (request-context-principal parent-context)
                                        (request-context-capabilities parent-context) #f cancelled? void))])
    (thread
     (lambda ()
       (with-handlers ([exn:fail? (lambda (e)
                                   (change! store id principal
                                     (lambda (state task) (hash-set state 'task (hash-set* task 'status "failed" 'lastUpdatedAt (timestamp)
                                                                                        'error (hasheq 'code -32603 'message (if (exn:fail:recovery? e) "Workflow requires manual recovery" "Task execution failed")))))))])
         (define state (stored-instance-state (owned store id principal)))
         (unless (terminal? (hash-ref state 'task))
           (define result (run-workflow workflow store (stored-instance-arguments instance) #:principal principal
                                        #:state (hash-ref state 'workflow) #:responses (hash-ref state 'responses (hasheq)) #:adapters adapters
                                        #:cancelled? cancelled?))
           (change! store id principal
             (lambda (state task)
               (hash-set state 'task
                         (if (equal? (hash-ref result 'resultType) "input_required")
                             (hash-set* task 'status "input_required" 'lastUpdatedAt (timestamp) 'inputRequests (hash-ref result 'inputRequests))
                             (hash-set* (hash-remove task 'inputRequests) 'status "completed" 'lastUpdatedAt (timestamp) 'result result)))))))))))
(define (start-workflow-task workflow store arguments principal #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)])
  (define expiry (+ (current-seconds) 86400))
  (define instance
    (store-transaction store
      (lambda ()
        (define flow (create-instance! store principal (workflow-descriptor-name workflow) arguments (workflow-descriptor-version workflow) (workflow-descriptor-fingerprint workflow) expiry
                                       (hasheq 'position 0 'values arguments 'status "working" 'effects (hasheq))))
        (define instance (create-instance! store principal (string-append "task:" (workflow-descriptor-name workflow)) arguments
                                           (workflow-descriptor-version workflow) (workflow-descriptor-fingerprint workflow) expiry (hasheq 'task (hasheq))))
        (define time (timestamp))
        (update-instance! store instance (hasheq 'workflow (stored-instance-handle flow)
                                                 'task (hasheq 'taskId (stored-instance-handle instance) 'status "working" 'createdAt time 'lastUpdatedAt time 'ttlMs 86400000 'pollIntervalMs 100))))))
  (resume-task! workflow store (stored-instance-handle instance) principal #:adapters adapters #:custodian custodian)
  (hash-set (hash-ref (stored-instance-state instance) 'task) 'resultType "task"))
(define (update-task! workflow store id principal responses #:adapters [adapters (hasheq)] #:custodian [custodian (current-custodian)])
  (store-transaction store
    (lambda ()
      (define instance (owned store id principal)) (define state (stored-instance-state instance)) (define task (hash-ref state 'task))
      (unless (equal? (hash-ref task 'status) "input_required") (error 'tasks/update "task is not awaiting input"))
      (unless (and (hash? responses) (for/and ([key (in-hash-keys responses)]) (hash-has-key? (hash-ref task 'inputRequests) key))) (error 'tasks/update "input response does not match a pending request"))
      (update-instance! store instance (hash-set* state 'responses responses 'task (hash-set task 'status "working")))))
  (resume-task! workflow store id principal #:adapters adapters #:custodian custodian)
  (hasheq 'resultType "complete"))
(define (cancel-task! store id principal)
  (change! store id principal (lambda (state task) (hash-set state 'task (hash-set* (hash-remove task 'inputRequests) 'status "cancelled" 'lastUpdatedAt (timestamp)))))
  (hasheq 'resultType "complete"))
