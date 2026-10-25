#lang racket/base
(require rackunit mcp mcp/tasks)
(define defaults 0)
(define keys '())
(workflow (immediate [optional Any #:optional] [fallback Integer #:default (begin (set! defaults (add1 defaults)) 7)])
  #:version "1" #:execution task-optional
  #:key (lambda (args) (set! keys (cons args keys)) (json->string args))
  (structured-result (hasheq 'optional (if (missing? optional) "absent" optional) 'fallback fallback)))
(workflow (boundary [optional Any #:optional] [fallback Integer #:default (begin (set! defaults (add1 defaults)) 7)])
  #:version "1" #:execution task
  (task-boundary launch)
  (structured-result (hasheq 'optional (if (missing? optional) "absent" optional) 'fallback fallback)))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list immediate boundary)) #:store store))
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(dynamic-wind void
  (lambda ()
    (for* ([name '("immediate" "boundary")] [value (list missing #f json-null)])
      (define before defaults)
      (define receipt (dispatch rt "tools/call"
                        (hasheq '_meta (request-meta #:capabilities caps) 'name name
                                'arguments (if (missing? value) (hasheq) (hasheq 'optional value)))))
      (define result
        (let loop ([left 200])
          (define detail (dispatch rt "tasks/get" (hasheq '_meta (request-meta #:capabilities caps)
                                                         'taskId (hash-ref receipt 'taskId))))
          (cond [(equal? (hash-ref detail 'status) "completed") (hash-ref detail 'result)]
                [(zero? left) (error 'test "task did not complete: ~s" detail)]
                [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop (sub1 left))])))
      (check-equal? defaults (add1 before))
      (check-equal? (hash-ref result 'structuredContent)
                    (hasheq 'optional (if (missing? value) "absent" value) 'fallback 7))
      (when (equal? name "immediate")
        (check-equal? (car keys) (if (missing? value) (hasheq 'fallback 7) (hasheq 'optional value 'fallback 7)))
        (define plain (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name name
                        'arguments (if (missing? value) (hasheq) (hasheq 'optional value)))))
        (check-equal? plain result))))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
