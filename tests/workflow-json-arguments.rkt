#lang racket/base
(require rackunit racket/file mcp mcp/private/render-provenance)
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

(define numeric-input
  (hasheq 'mode "form" 'message "Number?" 'requestedSchema (object-schema (hasheq 'n Number))))
(workflow (numeric-response) #:version "1"
  (await-input [answer Any] numeric-input)
  (structured-result answer))
(workflow (numeric-group) #:version "1"
  (await-input ([first Any numeric-input] [second Any numeric-input]))
  (structured-result (list first second)))
(workflow (numeric-boundary) #:version "1" #:execution task-optional
  (await-input [answer Any] numeric-input)
  (task-boundary launch)
  (structured-result answer))
(define numeric-answer (hasheq 'action "accept" 'content (hasheq 'n 1.0)))
(define changed-answer (hasheq 'action "accept" 'content (hasheq 'n 2.0)))
(define exact-answer (string->json (json->string numeric-answer)))
(define (response-conflict? failure)
  (and (exn:fail:mcp? failure) (= (exn:fail:mcp-code failure) -32602)))

(test-case "low-level completed input compares represented JSON numbers"
  (define state (open-memory-store))
  (define program (tool-descriptor-workflow numeric-response))
  (dynamic-wind void
    (lambda ()
      (define initial (run-workflow program state (hasheq) #:principal "alice"))
      (define token (hash-ref initial 'requestState))
      (define (resume answer)
        (run-workflow program state (hasheq) #:principal "alice" #:state token #:responses (hasheq 'answer answer)))
      (define done (resume numeric-answer))
      (check-equal? (hash-ref done 'structuredContent) exact-answer)
      (define before (list-instances state))
      (check-equal? (resume numeric-answer) done)
      (check-exn response-conflict? (lambda () (resume changed-answer)))
      (check-equal? (list-instances state) before))
    (lambda () (close-store! state))))

(for ([mode '(single group partial boundary)])
  (test-case (format "native numeric response survives restart: ~a" mode)
    (define directory (make-temporary-file "numeric-response-~a" 'directory))
    (define state-path (build-path directory "state.sqlite"))
    (define state (open-sqlite-store state-path))
    (define interface (make-interface #:tools (list numeric-response numeric-group numeric-boundary)))
    (define runtime (make-runtime interface #:store state))
    (define sync-caps (hasheq 'elicitation (hasheq)))
    (define name (case mode [(group partial) "numeric-group"] [(boundary) "numeric-boundary"] [else "numeric-response"]))
    (define params (hasheq 'name name))
    (define (request method params capabilities)
      (dispatch runtime method (hash-set params '_meta (request-meta #:capabilities capabilities)) #:principal "alice"))
    (dynamic-wind void
      (lambda ()
        (define initial (request "tools/call" params sync-caps))
        (define handle (stored-instance-handle (car (list-instances state #:operation name))))
        (define retry (hash-set params 'requestState (hash-ref initial 'requestState)))
        (when (eq? mode 'partial)
          (define partial (request "tools/call" (hash-set retry 'inputResponses (hasheq 'first numeric-answer)) sync-caps))
          (check-equal? (hash-keys (hash-ref partial 'inputRequests)) '(second)))
        (custodian-shutdown-all (runtime-custodian runtime))
        (close-store! state)
        (set! state (open-sqlite-store state-path))
        (set! runtime (make-runtime interface #:store state))
        (define answers (if (memq mode '(group partial))
                            (hasheq 'first numeric-answer 'second numeric-answer) (hasheq 'answer numeric-answer)))
        (define submitted (hash-set retry 'inputResponses answers))
        (define resumed (request "tools/call" submitted caps))
        (define done
          (if (eq? mode 'boundary)
              (begin
                (check-equal? (hash-ref resumed 'resultType) "task")
                (let loop ([left 200])
                  (define task (request "tasks/get" (hasheq 'taskId (hash-ref resumed 'taskId)) caps))
                  (cond [(equal? (hash-ref task 'status) "completed") (hash-ref task 'result)]
                        [(zero? left) (error 'test "numeric task did not complete")]
                        [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop (sub1 left))])))
              resumed))
        (check-equal? (hash-ref done 'structuredContent)
                      (if (memq mode '(group partial)) (list exact-answer exact-answer) exact-answer))
        (check-equal? (request "tools/call" submitted caps) resumed)
        (define before (list-instances state))
        (check-exn response-conflict?
          (lambda () (request "tools/call" (hash-set retry 'inputResponses
            (hash-set answers (if (memq mode '(group partial)) 'first 'answer) changed-answer)) caps)))
        (check-equal? (list-instances state) before)
        (check-equal? (map stored-instance-handle (list-instances state #:operation name)) (list handle)))
      (lambda () (custodian-shutdown-all (runtime-custodian runtime)) (close-store! state)
        (delete-directory/files directory)))))
