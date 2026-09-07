#lang racket/base
(require rackunit racket/async-channel mcp)

(for* ([policy '(transactional manual idempotent)] [cancel? '(#f #t)])
  (define entered (make-async-channel))
  (define release (make-semaphore 0))
  (define preparations 0)
  (define effects 0)
  (define store (open-memory-store))
  (define program
    (make-workflow "blocked-effect-input" "1" "effect-input-lock"
      (list (workflow-stage 'effect 'effect Integer
              (lambda (_env)
                (set! preparations (add1 preparations))
                (async-channel-put entered (cons (current-thread) (current-store-connection)))
                (semaphore-wait release) 7) 'write policy)
            (workflow-stage 'done 'complete #t (lambda (_env) (text-result "done")) #f #f))))
  (define adapters
    (hasheq 'write (effect-adapter policy
      (lambda (input _key connection)
        (check-equal? input 7)
        (check-eq? connection (and (eq? policy 'transactional) (state-store-connection store)))
        (set! effects (add1 effects))
        (committed-result input '("changed"))))))
  (define tool (make-tool "blocked-effect-input" '() (lambda (_args) (error 'test "workflow bypassed"))
                          #:workflow program #:execution 'task))
  (define rt (make-runtime (make-interface #:tools (list tool)) #:store store #:adapters adapters))
  (define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
  (define (call method params)
    (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps))))
  (define (bounded-call method params)
    (define answers (make-async-channel))
    (parameterize ([current-custodian (runtime-custodian rt)])
      (thread (lambda () (async-channel-put answers (call method params)))))
    (sync/timeout 2 answers))
  (dynamic-wind void
    (lambda ()
      (define task (call "tools/call" (hasheq 'name "blocked-effect-input")))
      (define params (hasheq 'taskId (hash-ref task 'taskId)))
      (define entry (sync/timeout 5 entered))
      (check-not-false entry)
      (unless entry (error 'test "input preparation did not start"))
      (check-false (cdr entry))
      (define polled (bounded-call "tasks/get" params))
      (check-equal? (and polled (hash-ref polled 'status)) "working")
      (when cancel?
        (check-equal? (bounded-call "tasks/cancel" params) (hasheq 'resultType "complete")))
      (semaphore-post release)
      (check-not-false (sync/timeout 5 (car entry)))
      (check-equal? preparations 1)
      (check-equal? effects (if cancel? 0 1))
      (define final (call "tasks/get" params))
      (check-equal? (hash-ref final 'status) (if cancel? "cancelled" "completed"))
      (define task-row (load-instance store (hash-ref task 'taskId)))
      (define flow (load-instance store (hash-ref (stored-instance-state task-row) 'workflow)))
      (define state (stored-instance-state flow))
      (check-equal? (hash-ref state 'position) (if cancel? 0 1))
      (check-equal? (hash-has-key? (hash-ref state 'values) 'effect) (not cancel?))
      (when cancel?
        (check-equal? (hash-ref state 'effects) (hasheq))
        (check-false (hash-has-key? state 'result)))
      (check-equal? (length (list-instances store #:operation "change-outbox")) (if cancel? 0 1)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))

;; An uncertain manual effect rejects retries before another input computation.
(define store (open-memory-store))
(define preparations 0)
(define program
  (make-workflow "uncertain-input" "1" "effect-input-lock"
    (list (workflow-stage 'effect 'effect Integer
            (lambda (_env) (set! preparations (add1 preparations)) 1) 'write 'manual)
          (workflow-stage 'done 'complete #t (lambda (_env) (text-result "done")) #f #f))))
(define adapters (hasheq 'write (effect-adapter 'manual (lambda args (error 'adapter "uncertain")))))
(dynamic-wind void
  (lambda ()
    (check-exn #rx"uncertain" (lambda () (run-workflow program store (hasheq) #:principal "alice" #:adapters adapters)))
    (define flow (car (list-instances store #:operation "uncertain-input")))
    (check-equal? preparations 1)
    (check-exn exn:fail:recovery?
      (lambda () (run-workflow program store (hasheq) #:principal "alice" #:adapters adapters #:state (stored-instance-handle flow))))
    (check-equal? preparations 1)
    (check-equal? (load-instance store (stored-instance-handle flow)) flow))
  (lambda () (close-store! store)))
