#lang racket/base
(require rackunit mcp mcp/private/render-provenance)
(define input (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
(define decimal-text (make-string-codec "decimal-text" "1" Number number->string string->number))
(workflow (decimal [n Number #:default 0.5] [nested Any #:default (hash 'n (list 1.0))]) #:version "1"
  #:key (lambda (args) (json->string args))
  (await-input [answer Any] input)
  (structured-result (list n nested)))
(prompt (decimal-prompt [n Number #:codec decimal-text #:default 0.5]) #:workflow "1"
  (await-input [answer Any] input)
  (role "user" (text-content (number->string n))))
(workflow (decimal-task [n Number #:default 0.5]) #:version "1" #:execution task
  #:key (lambda (args) (number->string (hash-ref args 'n)))
  (structured-result n))
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list decimal decimal-task) #:prompts (list decimal-prompt)) #:store store))
(define who (make-parameter "default"))
(define (call method params) (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal (who)))
(dynamic-wind void
  (lambda ()
    (for ([args (list (hasheq) (hasheq 'n 0.5 'nested (hash 'n (list 1.0))))])
      (test-case "inexact arguments and defaults survive initial save and keyed replay"
        (who (if (zero? (hash-count args)) "default" "explicit"))
        (define params (hasheq 'name "decimal" 'arguments args))
        (define waiting (call "tools/call" params))
        (check-equal? (hash-ref waiting 'resultType) "input_required")
        (define retry (hash-set* params 'requestState (hash-ref waiting 'requestState) 'inputResponses (hasheq 'answer (hasheq 'action "decline"))))
        (check-exn exn:fail? (lambda () (call "tools/call" (hash-set retry 'arguments (hasheq 'n 0.75)))))
        (define done (call "tools/call" retry))
        (check-equal? (hash-ref done 'structuredContent) (list 1/2 (hasheq 'n '(1))))
        (check-equal? (call "tools/call" params) done)))
    (for ([args (list (hasheq) (hasheq 'n "0.5"))])
      (test-case "prompt codec and default have the same persistent numeric identity"
        (define params (hasheq 'name "decimal-prompt" 'arguments args))
        (define waiting (call "prompts/get" params))
        (define done (call "prompts/get" (hash-set* params 'requestState (hash-ref waiting 'requestState)
          'inputResponses (hasheq 'answer (hasheq 'action "decline")))))
        (check-equal? (hash-ref done 'messages) (role "user" (text-content "1/2")))))
    (test-case "task creation deduplicates repeated inexact defaults"
      (define params (hasheq 'name "decimal-task"))
      (define task (call "tools/call" params))
      (check-equal? (call "tools/call" params) task)
      (check-not-false (find-instance-by-key store (who) "decimal-task" "0.5"))
      (define done
        (let loop ([left 200])
          (define detail (call "tasks/get" (hasheq 'taskId (hash-ref task 'taskId))))
          (cond [(equal? (hash-ref detail 'status) "completed") detail]
                [(zero? left) (error 'test "task did not complete: ~s" detail)]
                [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop (sub1 left))])))
      (check-equal? (hash-ref (hash-ref done 'result) 'structuredContent) 1/2))
    (test-case "argument normalization preserves trusted rendering provenance only"
      (define marker (mark-render-value (hasheq '$mcp/embedding 0 'uri "data:///one") "embedding"))
      (define copied (string->json (json->string marker)))
      (define flow (make-workflow "argument-provenance" "1" "1"
        (list (workflow-stage 'done 'complete Any
          (lambda (env)
            (structured-result (list (render-value-kind (hash-ref env 'marked))
                                     (render-value-kind (hash-ref env 'copied))
                                     (hash-ref env 'n)))) #f #f))
        #:key (lambda (args) (number->string (hash-ref args 'n)))))
      (define args (hash 'marked marker 'copied copied 'n 0.5))
      (define result (run-workflow flow store args #:principal "alice"))
      (check-not-false (find-instance-by-key store "alice" "argument-provenance" "0.5"))
      (check-equal? (hash-ref result 'structuredContent) '("embedding" #f 1/2))
      (check-equal? (run-workflow flow store args #:principal "alice") result)))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
