#lang racket/base
(require rackunit racket/runtime-path mcp mcp/tasks)
(provide (all-from-out rackunit) start-evidence! record! finish! attempt settled require-event)
(define (start-evidence! _name) (void))
(define (record! id value) (displayln (string-append "OBSERVATION " id " " (json->string value))))
(define (finish!) (void))
(define (attempt thunk)
  (with-handlers ([exn:fail? (lambda (e) (hasheq 'raised #t 'message (exn-message e)
    'code (if (exn:fail:mcp? e) (exn:fail:mcp-code e) 'null)))])
    (hasheq 'raised #f 'value (thunk))))
(define (settled store id [principal "alice"])
  (define deadline (+ (current-inexact-milliseconds) 3000))
  (let loop ()
    (define detail (get-task store id principal))
    (cond [(member (hash-ref detail 'status) '("completed" "failed" "input_required")) detail]
          [(>= (current-inexact-milliseconds) deadline) (error 'probe "task did not settle: ~s" detail)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop)])))
(define (require-event event)
  (or (sync/timeout 3 event) (error 'probe "synchronization deadline")))
