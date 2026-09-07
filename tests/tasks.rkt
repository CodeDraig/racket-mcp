#lang racket/base
(require rackunit mcp mcp/tasks mcp/subscription)
(workflow (later [name String]) #:version "1" #:execution task
  (checkpoint [message String] (string-append "Hi, " name))
  (await-input [answer Any] (hasheq 'mode "form" 'message "Approve?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (text-result message))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list later)) #:store store))
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define (call method params [principal "alice"])
  (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal principal))
(check-exn exn:fail:mcp? (lambda () (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "later" 'arguments (hasheq 'name "Ada")))))
(define task (call "tools/call" (hasheq 'name "later" 'arguments (hasheq 'name "Ada"))))
(check-equal? (hash-ref task 'resultType) "task")
(define id (hash-ref task 'taskId))
(define (await-status expected)
  (let loop ([remaining 100])
    (define task (call "tasks/get" (hasheq 'taskId id)))
    (cond [(equal? (hash-ref task 'status) expected) task]
          [(zero? remaining) (error 'test "task did not reach ~a; ~s" expected task)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 remaining))])))
(void (await-status "input_required"))
(check-exn exn:fail? (lambda () (call "tasks/get" (hasheq 'taskId id) "bob")))
(check-exn exn:fail? (lambda () (call "tasks/update" (hasheq 'taskId id 'inputResponses (hasheq 'wrong (hasheq 'action "decline"))))))
(check-equal? (call "tasks/update" (hasheq 'taskId id 'inputResponses (hasheq 'answer (hasheq 'action "accept" 'content (hasheq 'ok #t))))) (hasheq 'resultType "complete"))
(define final (await-status "completed"))
(check-equal? (hash-ref (hash-ref final 'result) 'content) (list (text-content "Hi, Ada")))
(void (call "tasks/cancel" (hasheq 'taskId id)))
(check-equal? (call "tasks/get" (hasheq 'taskId id)) final)
(workflow (detached) #:version "1" #:execution task
  (checkpoint [independent Boolean]
    (begin ((request-context-notify (current-request-context)) (hasheq 'unexpected #t))
           (not ((request-context-cancelled? (current-request-context))))))
  (text-result (if independent "detached" "inherited cancellation")))
(define detached-runtime (make-runtime (make-interface #:tools (list detached)) #:store store))
(define escaped-notifications '())
(define detached-task
  (parameterize ([current-cancelled? (lambda () #t)])
    (dispatch detached-runtime "tools/call"
              (hasheq '_meta (request-meta #:capabilities caps) 'name "detached")
              #:principal "alice" #:notify (lambda (v) (set! escaped-notifications (cons v escaped-notifications))))))
(define detached-final
  (let loop ([remaining 100])
    (define task (get-task store (hash-ref detached-task 'taskId) "alice"))
    (cond [(equal? (hash-ref task 'status) "completed") task]
          [(zero? remaining) (error 'test "detached task failed: ~s" task)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 remaining))])))
(check-equal? (hash-ref (hash-ref detached-final 'result) 'content) (list (text-content "detached")))
(check-equal? escaped-notifications '())
(custodian-shutdown-all (runtime-custodian detached-runtime))
(custodian-shutdown-all (runtime-custodian rt))
(close-store! store)
