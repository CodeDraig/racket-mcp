#lang racket/base
(require rackunit racket/file mcp)

(define defaults 0)
(define (next-default) (set! defaults (add1 defaults)) defaults)
(define integer-text (make-string-codec "integer-text" "1" Integer number->string string->number))
(define request (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
(workflow (tool-defaults [n Integer #:default (next-default)] [next Integer #:default (add1 n)])
  #:version "1"
  (await-input [first Any] request)
  (await-input [second Any] request)
  (structured-result (list n next)))
(workflow (other-tool [n Integer #:default (next-default)] [next Integer #:default (add1 n)])
  #:version "1"
  (await-input [first Any] request)
  (text-result "other"))
(prompt (prompt-defaults [n Integer #:codec integer-text #:default (next-default)]
                         [next Integer #:codec integer-text #:default (add1 n)])
  #:workflow "1"
  (await-input [first Any] request)
  (await-input [second Any] request)
  (role "user" (text-content (format "~s" (list n next)))))
(resource (resource-defaults [n Integer #:default (next-default)] [next Integer #:default (add1 n)])
  #:uri "defaults:///" #:workflow "1"
  (await-input [first Any] request)
  (await-input [second Any] request)
  (format "~s" (list n next)))
(define default-value #f)
(workflow (task-defaults [fallback Any #:default (begin (next-default) default-value)] [optional Any #:optional])
  #:version "1" #:execution task
  (await-input [first Any] request)
  (task-boundary launch)
  (structured-result (list (if (missing? fallback) "absent" fallback) (missing? optional))))
(define interface (make-interface #:tools (list tool-defaults other-tool task-defaults)
                                  #:prompts (list prompt-defaults) #:resources (list resource-defaults)))
(define meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))))
(define decline (hasheq 'action "decline"))

(for ([method '("tools/call" "prompts/get" "resources/read")]
      [target (list (hasheq 'name "tool-defaults") (hasheq 'name "prompt-defaults") (hasheq 'uri "defaults:///"))])
  (test-case (string-append method " reuses defaults across rounds and restart")
    (define directory (make-temporary-file "mcp-workflow-defaults-~a" 'directory))
    (define path (build-path directory "state.sqlite"))
    (define store (open-sqlite-store path))
    (define rt (make-runtime interface #:store store))
    (define (restart!)
      (custodian-shutdown-all (runtime-custodian rt))
      (close-store! store)
      (set! store (open-sqlite-store path))
      (set! rt (make-runtime interface #:store store)))
    (define (call params [principal "alice"])
      (dispatch rt method (hash-set params '_meta meta) #:principal principal))
    (dynamic-wind void
      (lambda ()
        (set! defaults 0)
        (define initial (call target))
        (check-equal? defaults 1)
        (define retry (hash-set* target 'requestState (hash-ref initial 'requestState)
                                 'inputResponses (hasheq 'first decline)))
        (restart!)
        (check-exn exn:fail? (lambda () (call retry "bob")))
        (check-exn exn:fail? (lambda () (call (hash-set retry 'requestState "unknown"))))
        (when (equal? method "tools/call")
          (check-exn exn:fail? (lambda () (call (hash-set retry 'name "other-tool")))))
        (unless (equal? method "resources/read")
          (check-exn exn:fail?
            (lambda () (call (hash-set retry 'arguments (hasheq 'n (if (equal? method "prompts/get") "99" 99)))))))
        (define second (call retry))
        (check-equal? defaults 1)
        (check-not-equal? (hash-ref second 'requestState) (hash-ref initial 'requestState))
        (check-equal? (call retry) second)
        (restart!)
        (define done (call (hash-set* target 'requestState (hash-ref second 'requestState)
                                     'inputResponses (hasheq 'second decline))))
        (case (string->symbol method)
          [(tools/call) (check-equal? (hash-ref done 'structuredContent) '(1 2))]
          [(prompts/get) (check-equal? (hash-ref done 'messages) (role "user" (text-content "(1 2)")))]
          [(resources/read) (check-equal? (hash-ref (car (hash-ref done 'contents)) 'text) "(1 2)")])
        (check-equal? (call retry) done)
        (check-equal? defaults 1)
        ;; A fresh invocation still evaluates its defaults once.
        (check-equal? (hash-ref (call target) 'resultType) "input_required")
        (check-equal? defaults 2))
      (lambda ()
        (custodian-shutdown-all (runtime-custodian rt))
        (close-store! store)
        (delete-directory/files directory)))))

(test-case "task preparation preserves false, null, and absent defaults"
  (define store (open-memory-store))
  (define rt (make-runtime interface #:store store))
  (define task-meta
    (request-meta #:capabilities (hasheq 'elicitation (hasheq)
                                        'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))))
  (define params (hasheq '_meta task-meta 'name "task-defaults"))
  (dynamic-wind void
    (lambda ()
      (for ([value (in-list (list #f json-null missing))])
        (set! defaults 0)
        (set! default-value value)
        (define pending (dispatch rt "tools/call" params))
        (check-equal? defaults 1)
        ;; A changed default expression must not affect the prepared execution.
        (set! default-value "changed")
        (define retry (hash-set* params 'requestState (hash-ref pending 'requestState)
                                 'inputResponses (hasheq 'first decline)))
        (define receipt (dispatch rt "tools/call" retry))
        (check-equal? (hash-ref receipt 'resultType) "task")
        (check-equal? (dispatch rt "tools/call" retry) receipt)
        (define deadline (+ (current-inexact-milliseconds) 3000))
        (define done
          (let loop ()
            (define detail (dispatch rt "tasks/get" (hasheq '_meta task-meta 'taskId (hash-ref receipt 'taskId))))
            (cond [(equal? (hash-ref detail 'status) "completed") (hash-ref detail 'result)]
                  [(>= (current-inexact-milliseconds) deadline) (error 'test "task did not complete: ~s" detail)]
                  [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop)])))
        (check-equal? (hash-ref done 'structuredContent) (list (if (missing? value) "absent" value) #t))
        (check-equal? defaults 1)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
