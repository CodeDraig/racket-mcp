#lang racket/base
(require rackunit mcp (prefix-in fixture: "../dev/conformance-tasks.rkt"))
(define store (open-memory-store))
(define rt (make-runtime fixture:mcp-interface #:store store))
(define params (hasheq 'name "slow_compute" 'arguments (hasheq 'seconds 0 'label "test")))
(define plain (dispatch rt "tools/call" (hash-set params '_meta (request-meta))))
(check-equal? plain (text-result "Computed test"))
(check-false (hash-has-key? plain 'taskId))
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define async (dispatch rt "tools/call" (hash-set params '_meta (request-meta #:capabilities caps))))
(check-equal? (hash-ref async 'resultType) "task")
(define id (hash-ref async 'taskId))
(define final
  (let loop ([left 100])
    (define result (dispatch rt "tasks/get" (hasheq '_meta (request-meta #:capabilities caps) 'taskId id)))
    (cond [(equal? (hash-ref result 'status) "completed") result]
          [(zero? left) (error 'test "task failed to complete: ~s" result)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
(check-equal? (hash-ref final 'result) plain)
(check-exn (lambda (e) (and (exn:fail:mcp? e) (= (exn:fail:mcp-code e) -32021)))
  (lambda () (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "failing_job"))))
(check-exn exn:fail? (lambda () (make-tool "bad" '() void #:execution 'typo)))
(check-exn exn:fail? (lambda () (make-tool "bad" '() void #:execution 'task-optional)))
(custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
