#lang racket/base
(require rackunit racket/file racket/async-channel mcp mcp/tasks)
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define output (object-schema (hasheq 'n Integer)))
(define (wait-task store id)
  (let loop ([left 200])
    (define result (get-task store id "alice"))
    (cond [(member (hash-ref result 'status) '("completed" "failed" "input_required")) result]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop (sub1 left))])))
(for* ([delayed? '(#f #t)]
       [result (list (hasheq 'resultType "complete")
                     (text-result "missing structured output")
                     (structured-result (hasheq 'n "wrong"))
                     (structured-result (hasheq 'n 7))
                     (hash-set (text-result "application error") 'isError #t))])
  (test-case (format "task output ~s delayed ~s" result delayed?)
    (define flow
      (make-workflow "job" "1" "job/1"
        (append
          (if delayed? (list (workflow-stage 'answer 'input Any
                              (lambda (_) (hasheq 'mode "form" 'message "Continue?"
                                                  'requestedSchema (object-schema (hasheq)))) #f #f)) '())
          (list (workflow-stage 'done 'complete Any (lambda (_) result) #f #f)))))
    (define tool (make-tool "job" '() void #:workflow flow #:execution 'task #:output output))
    (define store (open-memory-store))
    (define rt (make-runtime (make-interface #:tools (list tool)) #:store store))
    (dynamic-wind void
      (lambda ()
        (define receipt (dispatch rt "tools/call" (hasheq '_meta meta 'name "job") #:principal "alice"))
        (define id (hash-ref receipt 'taskId))
        (when delayed?
          (check-equal? (hash-ref (wait-task store id) 'status) "input_required")
          (dispatch rt "tasks/update" (hasheq '_meta meta 'taskId id 'inputResponses
                                              (hasheq 'answer (hasheq 'action "decline"))) #:principal "alice"))
        (define final (wait-task store id))
        (define success? (or (equal? result (structured-result (hasheq 'n 7))) (hash-ref result 'isError #f)))
        (check-equal? (hash-ref final 'status) (if success? "completed" "failed"))
        (when success? (check-equal? (hash-ref final 'result) result))
        (when (equal? result (structured-result (hasheq 'n 7)))
          ;; Old SDKs could save an invalid success. Polling must not return it
          ;; or silently modify the record when no recovery was requested.
          (define instance (load-instance store id))
          (define state (stored-instance-state instance))
          (define legacy (update-instance! store instance
                           (hash-set state 'task (hash-set (hash-ref state 'task) 'result
                                                   (structured-result (hasheq 'n "legacy bad"))))))
          (check-exn #rx"declared schema"
            (lambda () (dispatch rt "tasks/get" (hasheq '_meta meta 'taskId id) #:principal "alice")))
          (check-equal? (load-instance store id) legacy)))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))))

(for ([runtime-recovery? '(#f #t)])
  (test-case (format "output contract survives restart, runtime recovery ~s" runtime-recovery?)
    (define directory (make-temporary-file "task-contract-~a" 'directory))
    (define path (build-path directory "state.sqlite"))
    (define store (open-sqlite-store path))
    (define entered (make-semaphore))
    (define blocked? #t)
    (define flow (make-workflow "restart" "1" "restart/1"
                  (list (workflow-stage 'done 'complete Any
                          (lambda (_)
                            (when blocked? (semaphore-post entered) (sync never-evt))
                            (structured-result (hasheq 'n "bad"))) #f #f))))
    (define iface (make-interface #:tools (list (make-tool "restart" '() void #:workflow flow #:execution 'task #:output output))))
    (define rt (make-runtime iface #:store store))
    (dynamic-wind void
      (lambda ()
        (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "restart") #:principal "alice") 'taskId))
        (check-not-false (sync/timeout 5 entered))
        (custodian-shutdown-all (runtime-custodian rt))
        (when runtime-recovery?
          ;; Legacy tasks have no saved outputSchema; the runtime supplies it.
          (define instance (load-instance store id))
          (update-instance! store instance (hash-remove (stored-instance-state instance) 'outputSchema)))
        (close-store! store)
        (set! store (open-sqlite-store path))
        (set! rt (make-runtime iface #:store store))
        (set! blocked? #f)
        (if runtime-recovery?
            (recover-runtime-tasks! rt)
            (resume-task! flow store id "alice" #:custodian (runtime-custodian rt)))
        (check-equal? (hash-ref (wait-task store id) 'status) "failed"))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store) (delete-directory/files directory)))))

(test-case "invalid completion publishes failure, never success"
  (define store (open-memory-store))
  (define custodian (make-custodian))
  (define notifications (make-async-channel))
  (define flow (make-workflow "notify" "1" "notify/1"
                (list (workflow-stage 'done 'complete Any (lambda (_) (structured-result (hasheq 'n "bad"))) #f #f))))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-task-notify (lambda (_ detail) (async-channel-put notifications detail))])
        (start-workflow-task flow store (hasheq) "alice" #:output-schema output #:custodian custodian))
      (define notice (sync/timeout 5 notifications))
      (check-not-false notice)
      (check-equal? (hash-ref notice 'status) "failed")
      (check-false (sync/timeout 0 notifications)))
    (lambda () (custodian-shutdown-all custodian) (close-store! store))))

(test-case "repaired effects are not replayed when task output is invalid"
  (define calls 0)
  (workflow (repair) #:version "1" #:execution task
    (perform [value Integer] #:adapter writer #:policy manual 1)
    (text-result (number->string value)))
  (define tool (struct-copy tool-descriptor repair [output-schema output]))
  (define store (open-memory-store))
  (define rt (make-runtime (make-interface #:tools (list tool)) #:store store
               #:adapters (hasheq 'writer (effect-adapter 'manual
                 (lambda (_value _key _connection) (set! calls (add1 calls)) (error 'effect "uncertain"))))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "repair") #:principal "alice") 'taskId))
      (check-equal? (hash-ref (wait-task store id) 'status) "failed")
      (define flow-id (hash-ref (stored-instance-state (load-instance store id)) 'workflow))
      (recover-workflow! store flow-id 'value 'outcome #:outcome 7 #:principal "alice")
      (define replacement (retry-runtime-task! rt id #:principal "alice" #:capabilities caps))
      (check-equal? (hash-ref (wait-task store (hash-ref replacement 'taskId)) 'status) "failed")
      (check-equal? calls 1))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))

(test-case "replacement restart retains its own explicitly selected output schema"
  (define store (open-memory-store))
  (define custodian (make-custodian))
  (define entered (make-semaphore))
  (define blocked? #t)
  (define calls 0)
  (workflow (replacement) #:version "1" #:execution task
    (perform [value Integer] #:adapter writer #:policy manual 1)
    (structured-result
      (begin (when blocked? (semaphore-post entered) (sync never-evt))
             (hasheq 'n "bad"))))
  (define flow (tool-descriptor-workflow replacement))
  (define adapters (hasheq 'writer (effect-adapter 'manual
                      (lambda (_value _key _connection) (set! calls (add1 calls)) (error 'effect "uncertain")))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (start-workflow-task flow store (hasheq) "alice"
                            #:adapters adapters #:custodian custodian) 'taskId))
      (check-equal? (hash-ref (wait-task store id) 'status) "failed")
      (recover-workflow! store (hash-ref (stored-instance-state (load-instance store id)) 'workflow)
                         'value 'outcome #:outcome 7 #:principal "alice")
      (define next (retry-recovered-task! flow store id "alice" #:adapters adapters
                     #:custodian custodian #:output-schema output))
      (check-not-false (sync/timeout 5 entered))
      (custodian-shutdown-all custodian)
      (set! custodian (make-custodian))
      (set! blocked? #f)
      (define restarted (retry-recovered-task! flow store id "alice" #:adapters adapters #:custodian custodian))
      (check-equal? (hash-ref restarted 'taskId) (hash-ref next 'taskId))
      (check-equal? (hash-ref (wait-task store (hash-ref next 'taskId)) 'status) "failed")
      (check-equal? calls 1))
    (lambda () (custodian-shutdown-all custodian) (close-store! store))))
