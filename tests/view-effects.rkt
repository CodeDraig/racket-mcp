#lang racket/base
(require rackunit racket/async-channel mcp mcp/http)
(module fragment mcp/lang
  (module declarations racket/base
    (require mcp)
    (workflow (mounted-write) #:version "1"
      (perform [written Integer] #:adapter writer #:policy idempotent 1)
      (structured-result written))
    (provide mounted-write))
  (require 'declarations)
  (mount (view (make-interface #:tools (list mounted-write))
               #:namespace "restricted/" #:allow-adapters '())))
(require (prefix-in fragment: (submod "." fragment)))
(define checkpoints 0)
(define effects 0)
(workflow (write-now) #:version "1"
  (checkpoint [saved Integer] (begin (set! checkpoints (add1 checkpoints)) 1))
  (perform [written Integer] #:adapter writer #:policy idempotent saved)
  (structured-result written))
(workflow (write-later) #:version "1" #:execution task
  (perform [written Integer] #:adapter writer #:policy idempotent 1)
  (structured-result written))
(workflow (write-after-input) #:version "1" #:execution task
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (perform [written Integer] #:adapter writer #:policy idempotent 1)
  (structured-result written))
(define entered (make-async-channel))
(workflow (interrupted) #:version "1" #:execution task
  (checkpoint [saved Integer] (begin (async-channel-put entered (current-thread)) (sync never-evt)))
  (perform [written Integer] #:adapter writer #:policy idempotent saved)
  (structured-result written))
(define adapter
  (versioned-effect-adapter 'idempotent
    (lambda (input _key _connection) (set! effects (add1 effects)) input) "1"))
(define base (make-interface #:tools (list write-now write-later)))
(define store (open-memory-store))
(define runtimes '())
(define (runtime interface #:adapters [adapters (hasheq 'writer adapter)])
  (define rt (make-runtime interface #:store store #:adapters adapters))
  (set! runtimes (cons rt runtimes)) rt)
(define (call rt name [extra (hasheq)])
  (dispatch rt "tools/call"
    (hash-set* extra 'name name '_meta
      (request-meta #:capabilities (hasheq 'elicitation (hasheq)
        'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))))))
(define (denied? failure)
  (and (exn:fail:mcp? failure) (= (exn:fail:mcp-code failure) -32001)))
(define (await-task rt id expected)
  (define deadline (+ (current-inexact-milliseconds) 3000))
  (let loop ()
    (define result (dispatch rt "tasks/get" (hasheq 'taskId id '_meta
      (request-meta #:capabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))))))
    (cond [(equal? (hash-ref result 'status) expected) result]
          [(>= (current-inexact-milliseconds) deadline) (error 'await-task "expected ~a, got ~a" expected result)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop)])))
(dynamic-wind void
  (lambda ()
    (define restricted (view base #:allow-adapters '()))
    (define rt (runtime restricted))
    (check-exn denied? (lambda () (call rt "write-now")))
    (check-exn denied? (lambda () (call rt "write-later")))
    (check-equal? checkpoints 0)
    (check-equal? effects 0)
    (check-equal? (list-instances store) '())
    ;; A missing adapter name is denied just like a configured forbidden name.
    (check-exn denied? (lambda () (call (runtime restricted #:adapters (hasheq)) "write-now")))
    (check-equal? (list-instances store) '())
    (define replaced (view restricted #:namespace "x/" #:allow-adapters '(writer)
                           #:adapters (hasheq 'writer adapter)))
    (check-exn denied? (lambda () (call (runtime (mount-interfaces replaced)) "x/write-now")))
    (check-equal? (hash-ref (interface-adapter-restrictions replaced)
                          (car (interface-descriptor-tools replaced))) '())
    (check-equal? (hash-ref (call (runtime (view base #:allow-adapters '(writer))) "write-now")
                           'structuredContent) 1)
    (check-equal? checkpoints 1)
    (check-equal? effects 1)
    ;; An ordinary handler can construct a workflow dynamically. Adapter lookup
    ;; still enforces the operation's restriction before its first checkpoint.
    (define dynamic
      (make-tool "dynamic" '()
        (lambda (_)
          (run-workflow (tool-descriptor-workflow write-now) (current-workflow-store)
                        (hasheq) #:principal "local" #:adapters (current-workflow-adapters)))))
    (check-exn denied?
      (lambda () (call (runtime (view (make-interface #:tools (list dynamic)) #:allow-adapters '())) "dynamic")))
    (check-equal? checkpoints 1)
    ;; Nested dispatch cannot broaden the parent restriction through a different
    ;; unrestricted runtime or a fresh set of adapter replacements.
    (define child (runtime base))
    (define nesting (make-tool "nesting" '() (lambda (_) (call child "write-now"))))
    (check-exn denied?
      (lambda () (call (runtime (view (make-interface #:tools (list nesting)) #:allow-adapters '())) "nesting")))
    (check-equal? effects 1)
    (check-exn exn:fail? (lambda () (view base #:allow-adapters '("writer"))))
    (check-exn #rx"absent declaration"
      (lambda () (make-interface #:adapter-restrictions (hasheq write-now '()))))
    (define rules (make-hasheq (list (cons write-now '()))))
    (define copied (make-interface #:tools (list write-now) #:adapter-restrictions rules))
    (hash-set! rules write-now '(writer))
    (check-equal? (hash-ref (interface-adapter-restrictions copied) write-now) '())
    (check-equal? (hash-count (interface-adapter-restrictions (view copied #:exclude '("write-now")))) 0)
    (define summary (car (interface-effect-summary restricted)))
    (check-equal? (hash-ref summary 'hostEffects) "unknown")
    (check-equal? (hash-ref summary 'declaredAdapters) '("writer"))
    (check-equal? (hash-ref summary 'allowedAdapters) '())
    (check-equal? (hash-ref summary 'adapterPolicy) "allowlist")
    (check-exn denied? (lambda () (call (runtime fragment:mcp-interface) "restricted/mounted-write")))
    (for ([configuration '((local #f) (stdio #f) (http #f) (http #t))])
      (call-with-scenario-session restricted
        (lambda (session)
          (define outcome
            (with-handlers ([exn:fail:http:authorization? values])
              (scenario-call session "tools/call" (hasheq 'name "write-now"))))
          (if (exn:fail:http:authorization? outcome)
              (check-equal? (exn:fail:http:authorization-status outcome) 403)
              (check-equal? (hash-ref (hash-ref outcome 'error) 'code) -32001))
          (check-equal? (list-instances (scenario-session-store session)) '()))
        #:transport (car configuration) #:adapters (hasheq 'writer adapter) #:sse? (cadr configuration)))
    (check-equal? checkpoints 1)
    (check-equal? effects 1)
    ;; Task updates deny before recording input; an allowed retry still works.
    (define waiting-base (make-interface #:tools (list write-after-input)))
    (define permitted-rt (runtime waiting-base))
    (define task (call permitted-rt "write-after-input"))
    (define task-id (hash-ref task 'taskId))
    (await-task permitted-rt task-id "input_required")
    (define pending-instance (load-instance store task-id))
    (define restricted-rt (runtime (view waiting-base #:allow-adapters '())))
    (define task-update (hasheq 'taskId task-id 'inputResponses
      (hasheq 'answer (hasheq 'action "accept" 'content (hasheq 'ok #t))) '_meta
      (request-meta #:capabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
    (check-exn denied? (lambda () (dispatch restricted-rt "tasks/update" task-update)))
    (check-equal? (stored-instance-revision (load-instance store task-id)) (stored-instance-revision pending-instance))
    (check-equal? effects 1)
    (dispatch permitted-rt "tasks/update" task-update)
    (check-equal? (hash-ref (await-task permitted-rt task-id "completed") 'status) "completed")
    (check-equal? effects 2)
    ;; A task worker killed during a checkpoint is recovered through the new
    ;; runtime's restricted adapter map, without entering the checkpoint again.
    (define recovery-base (make-interface #:tools (list interrupted)))
    (define old-rt (runtime recovery-base))
    (define recovering-task (call old-rt "interrupted"))
    (define worker (sync/timeout 3 entered))
    (check-true (thread? worker))
    (custodian-shutdown-all (runtime-custodian old-rt))
    (check-not-false (sync/timeout 3 worker))
    (define recovered-rt (runtime (view recovery-base #:allow-adapters '())))
    (check-equal? (hash-ref (await-task recovered-rt (hash-ref recovering-task 'taskId) "failed") 'status) "failed")
    (check-false (sync/timeout 0 entered))
    (check-equal? effects 2))
  (lambda ()
    (for ([rt runtimes]) (custodian-shutdown-all (runtime-custodian rt)))
    (close-store! store)))
