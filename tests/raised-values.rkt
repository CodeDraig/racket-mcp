#lang racket/base
(require rackunit racket/list racket/port racket/file (prefix-in db: db) mcp mcp/stdio mcp/tasks)
(struct unprintable () #:property prop:custom-write (lambda args (error 'printer "must not print raised payload")))
(define payloads (list #f 'deliberate (vector 'private) (unprintable) (exn "base exception" (current-continuation-marks))))
(define payload #f)
(define rt (make-runtime (make-interface #:tools (list (make-tool "fail" '() (lambda (_) (raise payload)))
                                                     (make-tool "ok" '() (lambda (_) (text-result "ok")))))))
(define message (hasheq 'jsonrpc "2.0" 'id 7 'method "tools/call" 'params (hasheq '_meta (request-meta) 'name "fail")))
(for ([value (in-list payloads)])
  (set! payload value)
  (check-equal? (dispatch-message rt message)
                (hasheq 'jsonrpc "2.0" 'id 7 'error (hasheq 'code -32603 'message "Internal error"))))
(define interrupted (let/ec k (exn:break "interrupted" (current-continuation-marks) k)))
(set! payload interrupted)
(check-exn (lambda (value) (eq? value interrupted)) (lambda () (dispatch-message rt message)))
(set! payload (unprintable))
(define-values (server-in client-out) (make-pipe))
(define-values (client-in server-out) (make-pipe))
(define server (thread (lambda () (serve-stdio rt #:input server-in #:output server-out #:workers 1))))
(define client (make-stdio-client client-in client-out))
(dynamic-wind void
  (lambda ()
    (define reply (sync/timeout 5 (client-request client "tools/call" (hasheq 'name "fail"))))
    (check-not-false reply)
    (check-equal? (hash-ref (hash-ref reply 'error) 'code) -32603)
    ;; Wait for the monitor to release the slot; listing also proves the reader
    ;; and writer survive the same-connection failure.
    (define healthy
      (let loop ([left 100])
        (define result (sync/timeout 5 (client-request client "tools/list")))
        (unless result (error 'test "healthy follow-up timed out"))
        (cond [(hash-has-key? result 'result) result]
              [(positive? left) (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop (sub1 left))]
              [else (error 'test "request slot was not released")])) )
    (check-equal? (length (hash-ref (hash-ref healthy 'result) 'tools)) 2))
  (lambda () (close-output-port client-out) (sync/timeout 5 server) (client-close! client)
             (close-output-port server-out) (custodian-shutdown-all (runtime-custodian rt))))
(define store (open-memory-store))
(define task-owner (make-custodian))
(define (finished id)
  (let loop ([left 500])
    (define task (get-task store id "owner"))
    (cond [(member (hash-ref task 'status) '("completed" "failed" "cancelled")) task]
          [(positive? left) (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))]
          [else (error 'test "task remained nonterminal")])) )
(dynamic-wind void
  (lambda ()
    (for ([value (in-list payloads)])
      (define program (make-workflow "raised" "1" "1" (list (workflow-stage 'done 'complete Any (lambda (_) (raise value)) #f #f))))
      (define id
        (parameterize ([current-task-notify (lambda args (raise (unprintable)))] [current-error-port (open-output-string)])
          (hash-ref (start-workflow-task program store (hasheq) "owner" #:custodian task-owner) 'taskId)))
      (define task (finished id))
      (check-equal? (hash-ref task 'status) "failed")
      (check-equal? (hash-ref (hash-ref task 'error) 'message) "Task execution failed"))
    (define count 0)
    (define manual
      (make-workflow "manual" "1" "1"
        (list (workflow-stage 'effect 'effect Any (lambda (_) "input") 'writer 'manual)
              (workflow-stage 'done 'complete Any (lambda (_) (text-result "done")) #f #f))))
    (define adapters (hasheq 'writer (effect-adapter 'manual (lambda (_input _key _connection) (set! count (add1 count)) (raise #f)))))
    (define id (hash-ref (start-workflow-task manual store (hasheq) "owner" #:adapters adapters #:custodian task-owner) 'taskId))
    (check-equal? (hash-ref (finished id) 'status) "failed")
    (check-equal? (hash-ref (hash-ref (get-task store id "owner") 'error) 'message) "Workflow requires manual recovery")
    (check-true (hash-has-key? (stored-instance-state (load-instance store id)) 'recovery))
    (sync (resume-task! manual store id "owner" #:adapters adapters #:custodian task-owner))
    (check-equal? count 1)
    (define complete-program
      (make-workflow "published" "1" "1" (list (workflow-stage 'done 'complete Any (lambda (_) (text-result "committed")) #f #f))
                     #:changes (lambda (_args _result) '("changed"))))
    (define result
      (parameterize ([current-workflow-change-publisher (lambda () (raise (unprintable)))] [current-error-port (open-output-string)])
        (run-workflow complete-program store (hasheq) #:principal "owner")))
    (check-equal? result (text-result "committed"))
    (check-equal? (length (list-instances store #:operation "change-outbox")) 1))
  (lambda () (custodian-shutdown-all task-owner) (close-store! store)))

(define state-path (make-temporary-file "mcp-raised-~a.sqlite"))
(dynamic-wind void
  (lambda ()
    (for ([storage (in-list (list (open-memory-store) (open-sqlite-store state-path)))])
      (dynamic-wind void
        (lambda ()
          (define connection (state-store-connection storage))
          (db:query-exec connection "CREATE TABLE mutation(value TEXT)")
          (for ([value (in-list (append payloads (list interrupted)))])
            (define observed
              (with-handlers ([(lambda (_) #t) values])
                (store-transaction storage
                  (lambda ()
                    (db:query-exec connection "INSERT INTO mutation VALUES ('rolled back')")
                    (store-transaction storage (lambda () (raise value)))))))
            (check-eq? observed value)
            (check-false (db:in-transaction? connection))
            (check-equal? (db:query-value connection "SELECT count(*) FROM mutation") 0))
          (store-transaction storage (lambda () (db:query-exec connection "INSERT INTO mutation VALUES ('committed')")))
          (check-equal? (db:query-value connection "SELECT value FROM mutation") "committed"))
        (lambda () (close-store! storage))))
    (define reopened (open-sqlite-store state-path))
    (dynamic-wind void
      (lambda () (check-equal? (db:query-list (state-store-connection reopened) "SELECT value FROM mutation") '("committed")))
      (lambda () (close-store! reopened))))
  (lambda () (delete-file state-path)))
