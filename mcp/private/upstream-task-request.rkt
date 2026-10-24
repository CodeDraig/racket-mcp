#lang racket/base
(require racket/list
         "../storage.rkt"
         "../error.rkt"
         (only-in "../tasks.rkt" current-task-notify)
         (submod "../upstream-bridge.rkt" private)
         "upstream-task-state.rkt"
         "task-time.rkt"
         "task-schema.rkt"
         "input-response.rkt"
         "failure.rkt")
(provide upstream-task-request)
(define (upstream-task-request bridge store snapshot request source method id
                               #:principal principal #:credential-id credential
                               #:responses [responses (hasheq)] #:capabilities [capabilities (hasheq)]
                               #:observed [supplied-observation #f] #:validate-detail [validate-detail void]
                               #:verify [verify void] #:cancelled? [cancelled? (lambda () #f)] #:retry? [retry? #f])
  (check-capabilities! capabilities)
  (unless (member method '("tasks/get" "tasks/update" "tasks/cancel")) (error 'upstream-task "unknown method"))
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'upstream-task "task requests must own their transaction boundaries"))
  (unless (hash? responses) (mcp-error -32602 "Input responses must be an object"))
  (set! responses (freeze bridge responses))
  (define (latest) (owned bridge store snapshot id principal credential source))
  (define initial (latest))
  (define observation (and supplied-observation (freeze bridge supplied-observation)))
  (when observation
    (unless (and (equal? method "tasks/get") (task-schema-valid? "GetTaskResult" observation)
                 (equal? (hash-ref observation 'taskId) (hash-ref (stored-instance-state initial) 'remoteId)))
      (mcp-error -32603 "Malformed or unrelated upstream task observation")))
  (define answer #f)
  (define changed #f)
  (define (execute)
    (let loop ()
      (when (cancelled?) (error 'upstream-task "request cancelled"))
      (define action
        (store-transaction store
          (lambda ()
            (define instance (latest))
            (define state (stored-instance-state instance))
            (define command (hash-ref state 'command))
            (for ([(key response) (in-hash responses)] #:when (hash-has-key? (hash-ref state 'history) key))
              (unless (equal? response (hash-ref (hash-ref state 'history) key))
                (mcp-error -32602 "Conflicting upstream task input response")))
            (cond
              [(terminal? state)
               (list 'return (if (equal? method "tasks/get") (local-detail state capabilities) (hasheq 'resultType "complete")))]
              [command
               (cond [(equal? (hash-ref command 'status) "intent")
                      (set! changed (fail-uncertain! bridge store instance)) (list 'again)]
                     [else
                      (define task (hash-remove (hash-ref state 'task) 'inputRequests))
                      (define previous (hash-ref state 'remoteDetail #f))
                      (define retired (hash-ref state 'consumedInputDetails '()))
                      (define consumed
                        (if (and (equal? (hash-ref command 'method) "tasks/update") previous
                                 (equal? (hash-ref previous 'status #f) "input_required"))
                            (remove-duplicates (cons (detail-fingerprint previous) retired)) retired))
                      (set! changed (save! bridge store instance
                        (hash-set* state 'command #f 'lastCommand (hash-ref command 'method)
                          'consumedInputDetails consumed
                          'remoteInputs #f 'remoteDetail #f 'mapping (hasheq) 'accepted (hasheq)
                          'task (hash-set* task 'status "working" 'lastUpdatedAt (timestamp)))))
                      (if (equal? method "tasks/get") (list 'again) (list 'return (hasheq 'resultType "complete")))])]
              [(hash-ref state 'repairRetry #f)
               (cond [retry?
                      (define saved (hash-ref state 'repairRetry))
                      (unless (equal? method (hash-ref saved 'method)) (error 'upstream-task "retry method mismatch"))
                      (list 'send (hash-ref saved 'params))]
                     [(equal? method "tasks/get") (list 'return (local-detail state capabilities))]
                     [else (mcp-error -32602 "Task is awaiting operator retry dispatch")])]
              [retry? (list 'return (hasheq 'resultType "complete"))]
              [(equal? method "tasks/get") (list 'get (hash-ref state 'remoteId))]
              [(equal? method "tasks/cancel")
               (if (equal? (hash-ref state 'lastCommand #f) "tasks/cancel")
                   (list 'return (hasheq 'resultType "complete"))
                   (list 'send (hasheq 'taskId (hash-ref state 'remoteId))))]
              [else
               (define known (for/hasheq ([(key response) (in-hash responses)]
                                          #:when (hash-has-key? (hash-ref state 'mapping) key)) (values key response)))
               (cond [(zero? (hash-count known)) (list 'return (hasheq 'resultType "complete"))]
                     [else
                      (unless (equal? (hash-ref (hash-ref state 'task) 'status) "input_required")
                        (mcp-error -32602 "Upstream task is not awaiting input"))
                      (define accepted
                        (for/fold ([accepted (hash-ref state 'accepted)]) ([(key response) (in-hash known)])
                          (validate-input-response
                            (hash-ref (hash-ref (hash-ref (hash-ref state 'mapping) key) 'request) 'params) response)
                          (hash-set accepted key response)))
                      (define history
                        (for/fold ([history (hash-ref state 'history)]) ([(key response) (in-hash accepted)])
                          (hash-set history key response)))
                      (define task (hash-ref state 'task))
                      (set! changed (save! bridge store instance
                        (hash-set* state 'accepted accepted 'history history
                          'task (hash-set task 'inputRequests
                            (for/hasheq ([(key value) (in-hash (hash-ref task 'inputRequests))]
                                         #:unless (hash-has-key? accepted key)) (values key value))))))
                      (if (= (hash-count accepted) (hash-count (hash-ref state 'mapping)))
                          (list 'send (hasheq 'taskId (hash-ref state 'remoteId) 'inputResponses
                            (for/hasheq ([(key response) (in-hash accepted)])
                              (values (string->symbol (hash-ref (hash-ref (hash-ref state 'mapping) key) 'remote)) response))))
                          (list 'return (hasheq 'resultType "complete")))])]))))
      (case (car action)
        [(return) (cadr action)]
        [(again) (loop)]
        [(get)
         (unless observation (verify))
         (define outcome (or observation (freeze bridge (request "tasks/get" (hasheq 'taskId (cadr action))))))
         (when (and (not (hash-has-key? outcome 'resultType)) (hash-has-key? outcome 'error)) (mcp-error -32603 "Upstream task polling failed"))
         (define remote (if (hash-has-key? outcome 'resultType) outcome (hash-ref outcome 'result outcome)))
         (validate-detail remote)
         (define observed
           (store-transaction store
             (lambda ()
               (define prior (latest))
               (define state (stored-instance-state prior))
               (define current (hash-ref state 'remoteDetail #f))
               (when (and observation
                          (member (detail-fingerprint remote) (hash-ref state 'consumedInputDetails '()))
                          (not (and current (equal? (detail-fingerprint current) (detail-fingerprint remote)))))
                 (mcp-error -32603 "Superseded upstream task input observation; explicitly refresh the task"))
               (define saved (record-detail! bridge store prior remote))
               (unless (= (stored-instance-revision prior) (stored-instance-revision saved)) (set! changed saved))
               saved)))
         (local-detail (stored-instance-state observed) capabilities)]
        [(send)
         (verify)
         (store-transaction store
           (lambda ()
             (when (cancelled?) (error 'upstream-task "request cancelled"))
             (define instance (latest))
             (record-event! store id (hasheq 'kind "upstream-task-intent" 'method method))
             (save! bridge store instance (hash-set* (stored-instance-state instance) 'repairRetry #f 'command
               (hasheq 'status "intent" 'method method 'params (cadr action))))))
         (with-handlers ([non-break-failure?
                         (lambda (cause)
                           (store-transaction store (lambda () (set! changed (fail-uncertain! bridge store (latest)))))
                           (mcp-error -32603 "Upstream task mutation requires recovery"))])
           (define outcome (freeze bridge (request method (cadr action))))
           (when (and (not (hash-has-key? outcome 'resultType)) (hash-has-key? outcome 'error)) (error 'upstream-task "upstream mutation failed"))
           (define result (if (hash-has-key? outcome 'resultType) outcome (hash-ref outcome 'result outcome)))
           (unless (task-schema-valid? (if (equal? method "tasks/update") "UpdateTaskResult" "CancelTaskResult") result)
             (error 'upstream-task "malformed mutation response"))
           (store-transaction store
             (lambda ()
               (define instance (latest))
               (define state (stored-instance-state instance))
               (record-event! store id (hasheq 'kind "upstream-task-response" 'method method))
               (save! bridge store instance (hash-set state 'command
                 (hash-set (hash-ref state 'command) 'status "received"))))))
         (loop)])))
  (dynamic-wind void
    (lambda ()
      (let wait ()
        (when (cancelled?) (error 'upstream-task "request cancelled"))
        (unless (call-with-instance-worker store id (lambda () (set! answer (execute))))
          (sync (alarm-evt (+ (current-inexact-milliseconds) 25))) (wait)))
      answer)
    (lambda ()
      (when changed
        (with-handlers ([non-break-failure? (lambda (_) (void))])
          (store-transaction store
            (lambda ()
              (define now (load-instance store id))
              (when (= (stored-instance-revision now) (stored-instance-revision changed))
                ((current-task-notify) principal (hash-ref (stored-instance-state changed) 'task))))))))))
