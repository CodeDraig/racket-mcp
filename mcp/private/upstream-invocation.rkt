#lang racket/base
(require "upstream-snapshot.rkt" "handler-info.rkt" (only-in "upstream-task-state.rkt" adopt-upstream-task!)
         "../descriptor.rkt" "../workflow.rkt" "../authorization.rkt" "../error.rkt"
         "../upstream-bridge.rkt" (submod "../upstream-bridge.rkt" private))
(provide make-upstream-invocation durable-handler pending?)
(define (durable-handler bridge procedure) (if bridge (stateful-handler procedure) procedure))
(define (pending? result) (member (hash-ref result 'resultType #f) '("input_required" "task")))
(define (make-upstream-invocation snapshot request bridge)
  (define verified (make-hash)) (define lock (make-semaphore 1))
  (define (verify-for credential)
    (call-with-semaphore lock
      (lambda () (unless (hash-ref verified credential #f)
                   (check-upstream-compatibility! snapshot request) (hash-set! verified credential #t)))))
  (define (invoke method params [task-source #f])
    (define context (current-request-context))
    (define credential (and bridge ((upstream-bridge-credential-id bridge) (request-context-principal context))))
    (define (verify) (verify-for credential))
    (define durable? (and bridge (member method '("tools/call" "resources/read" "prompts/get"))))
    (define result
      (result!
       (if durable?
           (parameterize ([current-upstream-task-result
                           (and task-source
                             (lambda (parent capabilities)
                               (adopt-upstream-task! bridge (current-workflow-store) snapshot parent task-source capabilities)))])
           (bridge-upstream-request bridge (current-workflow-store) snapshot request method params
                                    #:principal (principal-key (request-context-principal context)) #:credential-id credential
                                    #:state (current-workflow-state) #:responses (current-workflow-responses)
                                    #:capabilities (request-context-capabilities context) #:key (current-workflow-invocation-key)
                                    #:cancelled? (request-context-cancelled? context) #:verify verify))
           (begin (verify) (request method params)))))
    (unless (or (equal? (hash-ref result 'resultType "complete") "complete")
                (and durable? (equal? (hash-ref result 'resultType #f) "input_required"))
                (and task-source (equal? (hash-ref result 'resultType #f) "task")))
      (mcp-error -32603 "Upstream outcome requires a supported durable translation for this operation"))
    (hash-set result 'resultType (hash-ref result 'resultType "complete")))
  (values invoke verify-for))
