#lang racket/base
(require rackunit mcp mcp/tasks)
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define output (object-schema (hasheq 'n Integer)))
(define (settled store id)
  (let loop ([left 500])
    (define detail (get-task store id "alice"))
    (cond [(member (hash-ref detail 'status) '("completed" "failed")) detail]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))

(for* ([flag (list "false" 0 json-null '() (hasheq))]
       [schema (list output #f)]
       [mode '(mrtr task legacy)])
  (test-case (format "non-Boolean isError cannot bypass ~a validation: ~s, schema ~s" mode flag schema)
    (define bad (hash-set (structured-result (hasheq 'n "bad")) 'isError flag))
    (define flow (make-workflow "job" "1" "job/1"
      (list (workflow-stage 'done 'complete Any (lambda (_) bad) #f #f))))
    (define task (make-tool "job" '() void #:workflow flow #:execution 'task #:output schema))
    (define plain (make-tool "plain" '() (lambda (_) bad) #:output schema))
    (define store (open-memory-store))
    (define rt (make-runtime (make-interface #:tools (list task plain)) #:store store))
    (dynamic-wind void
      (lambda ()
        (cond [(eq? mode 'mrtr)
               (check-exn exn:fail:mcp? (lambda ()
                 (dispatch rt "tools/call" (hasheq '_meta meta 'name "plain") #:principal "alice")))]
              [else
               (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "job") #:principal "alice") 'taskId))
               (define final (settled store id))
               (cond [(eq? mode 'task) (check-equal? (hash-ref final 'status) "failed")]
                     [else
                      (define instance (load-instance store id))
                      (define legacy (update-instance! store instance
                        (hash-set (stored-instance-state instance) 'task (hash-set* final 'status "completed" 'result bad))))
                      (check-exn exn:fail:mcp? (lambda ()
                        (dispatch rt "tasks/get" (hasheq '_meta meta 'taskId id) #:principal "alice")))
                      (check-equal? (load-instance store id) legacy)])]))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))))
