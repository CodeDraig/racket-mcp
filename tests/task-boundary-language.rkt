#lang racket/base
(require rackunit mcp mcp/tasks mcp/interaction)
(define (take-two xs) (list (car xs) (cadr xs)))
(define form (hasheq 'mode "form" 'message "Name?" 'requestedSchema (object-schema (hasheq 'name String))))
(workflow (optional) #:version "1" #:execution task-optional
  (await-input [answer Any] form)
  (task-boundary launch)
  (text-result (hash-ref (hash-ref answer 'content) 'name)))
(workflow (collision [launch String]) #:version "1" #:execution task-optional
  (task-boundary launch)
  (text-result launch))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list optional collision)) #:store store))
(define response (hasheq 'action "accept" 'content (hasheq 'name "Ada")))
(dynamic-wind void
  (lambda ()
    (check-equal?
     (hash-ref (dispatch rt "tools/call"
                         (hasheq '_meta (request-meta) 'name "collision" 'arguments (hasheq 'launch "retained"))
                         #:principal "alice") 'content)
     (list (text-content "retained")))
    (for ([task? '(#f #t)])
      (define caps (if task?
                       (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))
                       (hasheq 'elicitation (hasheq))))
      (define methods '())
      (define outcome
        (run-interaction
         (lambda (method params)
           (set! methods (append methods (list method)))
           (dispatch-message rt
             (hasheq 'jsonrpc "2.0" 'id (length methods) 'method method
                     'params (hash-set params '_meta (request-meta #:capabilities caps))) #:principal "alice"))
         "tools/call" (hasheq 'name "optional")
         #:elicit (lambda (_) response) #:navigate (lambda (_) (error 'test "unexpected navigation"))
         #:wait (lambda (_) (sync (alarm-evt (+ (current-inexact-milliseconds) 5))))))
      (define result (hash-ref outcome 'result))
      (check-equal? (take-two methods) '("tools/call" "tools/call"))
      (if task?
          (begin
            (check-not-false (member "tasks/get" methods))
            (check-equal? (hash-ref (hash-ref result 'result) 'content) (list (text-content "Ada"))))
          (begin
            (check-equal? methods '("tools/call" "tools/call"))
            (check-equal? (hash-ref result 'content) (list (text-content "Ada"))))))
    ;; The ordinary data API uses the same stage and handoff semantics.
    (define child
      (make-workflow "child" "1" "child/1"
        (list (workflow-stage 'child-boundary 'task-boundary Any (lambda (_) json-null) #f #f)
              (workflow-stage 'done 'complete Any (lambda (_) "child result") #f #f))))
    (define program
      (make-workflow "native" "1" "native/1"
        (list (workflow-stage 'child-result 'checkpoint String
                              (lambda (_) (run-workflow child store (hasheq) #:principal "alice")) #f #f)
              (workflow-stage 'answer 'input Any (lambda (_) form) #f #f)
              (workflow-stage 'launch 'task-boundary Any (lambda (_) json-null) #f #f)
              (workflow-stage 'done 'complete Any
                              (lambda (env) (text-result (hash-ref (hash-ref (hash-ref env 'answer) 'content) 'name))) #f #f))))
    (define first (start-workflow-task program store (hasheq) "alice" #:custodian (runtime-custodian rt)))
    (check-equal? (hash-ref first 'resultType) "input_required")
    (define task (start-workflow-task program store (hasheq) "alice" #:state (hash-ref first 'requestState)
                                      #:responses (hasheq 'answer response) #:custodian (runtime-custodian rt)))
    (check-equal? (hash-ref task 'resultType) "task")
    (check-equal? (for/sum ([instance (in-list (list-instances store))]
                           #:when (hash-has-key? (stored-instance-state instance) 'task)) 1) 2)
    (define ns (make-base-namespace))
    (parameterize ([current-namespace ns])
      (namespace-require 'mcp)
      (for ([bad (list '(task-boundary outside)
                       '(workflow (bad) #:version "1" (task-boundary 42) (text-result "no"))
                       '(workflow (bad) #:version "1" (task-boundary same) (task-boundary same) (text-result "no"))
                       '(workflow (bad) #:version "1" (text-result (task-boundary hidden))))])
        (check-exn exn:fail:syntax? (lambda () (expand (datum->syntax #f bad)))))))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
