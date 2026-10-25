#lang racket/base
(require rackunit racket/file racket/list mcp mcp/tasks)
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define (settled store id)
  (let loop ([left 500])
    (define detail (get-task store id "alice"))
    (cond [(member (hash-ref detail 'status) '("completed" "failed" "input_required")) detail]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))

(for* ([sqlite? '(#f #t)] [mode '(immediate input nested nested-input)]
       [action '(outcome retry abandon)] [raised? '(#f #t)])
  (test-case (format "embedded manual recovery: sqlite ~a, ~a, ~a, raised value ~a" sqlite? mode action raised?)
    (define path (and sqlite? (make-temporary-file "task-render-repair-~a.sqlite")))
    (define store (if path (open-sqlite-store path) (open-memory-store)))
    (define calls 0)
    (define keys '())
    (define parents 0)
    (define leading-reads 0)
    (define wrappers 0)
    (define fail? #t)
    (define allowed? #t)
    (define question (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
    (resource (leading) #:uri "repair:///leading" (set! leading-reads (add1 leading-reads)) "first")
    (resource (child) #:uri "repair:///child" #:workflow "1"
      (perform [value Integer] #:adapter writer #:policy manual 41)
      (number->string value))
    (resource (waiting) #:uri "repair:///waiting" #:workflow "1"
      (await-input [before Any] question)
      (perform [value Integer] #:adapter writer #:policy manual 41)
      (await-input [after Any] question)
      (number->string value))
    (resource (wrapper) #:uri "repair:///wrapper" #:workflow "1"
      (text-presentation (begin (set! wrappers (add1 wrappers))
                               (embed (if (eq? mode 'nested-input) (waiting) (child))))))
    (workflow (parent) #:version "1" #:execution task
      (hasheq 'resultType "complete" 'content
              (begin (set! parents (add1 parents))
                     (list (embed (leading)) (embed (case mode [(input) (waiting)] [(nested nested-input) (wrapper)] [else (child)]))))))
    (define iface (make-interface #:tools (list parent) #:resources (list leading child waiting wrapper)))
    (define adapters (hasheq 'writer (effect-adapter 'manual
      (lambda (value key _connection)
        (set! calls (add1 calls)) (set! keys (cons key keys))
        (if fail? (if raised? (raise 'uncertain) (error 'writer "uncertain result")) (add1 value))))))
    (define (make-rt) (make-runtime iface #:store store #:adapters adapters
      #:authorize (lambda (_principal _method _params) allowed?)))
    (define rt (make-rt))
    (define (update id detail)
      (dispatch rt "tasks/update" (hasheq '_meta meta 'taskId id 'inputResponses
        (for/hasheq ([key (in-hash-keys (hash-ref detail 'inputRequests))]) (values key (hasheq 'action "decline")))) #:principal "alice"))
    (define (reopen!)
      (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
      (set! store (open-sqlite-store path)) (set! rt (make-rt)))
    (dynamic-wind void
      (lambda ()
        (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "parent") #:principal "alice") 'taskId))
        (when (memq mode '(input nested-input))
          (define pending (settled store id))
          (check-equal? (hash-ref pending 'status) "input_required")
          (void (update id pending)))
        (define failed (settled store id))
        (check-equal? (hash-ref failed 'status) "failed")
        (check-equal? (hash-ref (hash-ref failed 'error) 'message) "Workflow requires manual recovery")
        (define instance (load-instance store id))
        (define recovery (hash-ref (stored-instance-state instance) 'recovery))
        (define child-id (stored-instance-handle (car (list-instances store #:operation
          (if (memq mode '(input nested-input)) "resources/read:waiting" "resources/read:child")))))
        (check-equal? (hash-ref recovery 'workflow) child-id)
        (when path (reopen!))
        (check-exn exn:fail? (lambda () (retry-runtime-task! rt id #:principal "alice" #:capabilities caps)))
        (recover-workflow! store child-id 'value action #:outcome 42 #:principal "alice")
        (set! fail? #f)
        (define records (list-instances store))
        (when (memq mode '(input nested-input))
          (check-exn exn:fail:mcp? (lambda () (retry-runtime-task! rt id #:principal "alice"
            #:capabilities (hash-remove caps 'elicitation))))
          (check-equal? (list-instances store) records))
        (set! allowed? #f)
        (check-exn exn:fail:mcp? (lambda () (retry-runtime-task! rt id #:principal "alice" #:capabilities caps)))
        (set! allowed? #t)
        (check-equal? (list-instances store) records)
        (cond [(eq? action 'abandon)
               (check-exn exn:fail? (lambda () (retry-runtime-task! rt id #:principal "alice" #:capabilities caps)))
               (check-equal? (list-instances store) records)]
              [else
        (define next (retry-runtime-task! rt id #:principal "alice" #:capabilities caps))
        (define next-id (hash-ref next 'taskId))
        (check-not-equal? next-id id)
        (when (memq mode '(input nested-input))
          (define pending (settled store next-id))
          (check-equal? (hash-ref pending 'status) "input_required")
          (when path (reopen!))
          (void (update next-id pending)))
        (define final (settled store next-id))
        (check-equal? (hash-ref final 'status) "completed")
        (check-equal? (map (lambda (content) (hash-ref (hash-ref content 'resource) 'text))
                           (hash-ref (hash-ref final 'result) 'content)) '("first" "42"))
        (check-equal? calls (if (eq? action 'retry) 2 1))
        (when (eq? action 'retry) (check-equal? (car keys) (cadr keys)))
        (when path (reopen!))
        (check-equal? (hash-ref (retry-runtime-task! rt id #:principal "alice" #:capabilities caps) 'taskId) next-id)])
        (check-equal? parents 1)
        (check-equal? leading-reads 1)
        (check-equal? wrappers (if (memq mode '(nested nested-input)) 1 0))
        (check-equal? (get-task store id "alice") failed)
        (check-equal? (stored-instance-revision (load-instance store id)) (stored-instance-revision instance)))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store) (when path (delete-file path))))))

(test-case "caught child failure does not turn an unrelated task failure into manual recovery"
  (define store (open-memory-store))
  (define child (make-workflow "caught-child" "1" "child/1"
    (list (workflow-stage 'value 'effect Integer (lambda (_) 41) 'writer 'manual)
          (workflow-stage 'done 'complete Any (lambda (_) (text-result "done")) #f #f))))
  (define payload (gensym 'child-failure))
  (define adapters (hasheq 'writer (effect-adapter 'manual (lambda args (raise payload)))))
  (define parent (make-workflow "caught-parent" "1" "parent/1"
    (list (workflow-stage 'done 'complete Any
      (lambda (_)
        (with-handlers ([(lambda (_) #t) void])
          (run-workflow child store (hasheq) #:principal "alice" #:adapters adapters))
        (error 'parent "unrelated failure")) #f #f))))
  (define rt (make-runtime (make-interface #:tools (list
    (make-tool "caught-parent" '() void #:workflow parent #:execution 'task))) #:store store))
  (dynamic-wind void
    (lambda ()
      ;; Standalone workflow failure still propagates the original raised value.
      (check-exn (lambda (value) (eq? value payload))
        (lambda () (run-workflow child store (hasheq) #:principal "alice" #:adapters adapters)))
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "caught-parent") #:principal "alice") 'taskId))
      (define failed (settled store id))
      (check-equal? (hash-ref failed 'status) "failed")
      (check-equal? (hash-ref (hash-ref failed 'error) 'message) "Task execution failed")
      (check-false (hash-has-key? (stored-instance-state (load-instance store id)) 'recovery)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))

(test-case "legacy parent recovery metadata remains eligible for replacement"
  (define store (open-memory-store))
  (define owner (make-custodian))
  (define calls 0)
  (define flow (make-workflow "legacy-parent" "1" "parent/1"
    (list (workflow-stage 'value 'effect Integer (lambda (_) 41) 'writer 'manual)
          (workflow-stage 'done 'complete Any (lambda (env) (text-result (number->string (hash-ref env 'value)))) #f #f))))
  (define adapters (hasheq 'writer (effect-adapter 'manual
    (lambda args (set! calls (add1 calls)) (error 'writer "uncertain")))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (start-workflow-task flow store (hasheq) "alice" #:adapters adapters #:custodian owner) 'taskId))
      (void (settled store id))
      (define instance (load-instance store id))
      (define state (stored-instance-state instance))
      (define recovery (hash-ref state 'recovery))
      (define legacy (update-instance! store instance (hash-set state 'recovery
        (for/hasheq ([key '(stage revision eventCount)]) (values key (hash-ref recovery key))))))
      (recover-workflow! store (hash-ref state 'workflow) 'value 'outcome #:outcome 42 #:principal "alice")
      (define replacement (retry-recovered-task! flow store id "alice" #:adapters adapters #:custodian owner))
      (define final (settled store (hash-ref replacement 'taskId)))
      (check-equal? (hash-ref final 'status) "completed")
      (check-equal? (hash-ref final 'result) (text-result "42"))
      (check-equal? calls 1)
      (check-equal? (load-instance store id) legacy))
    (lambda () (custodian-shutdown-all owner) (close-store! store))))
