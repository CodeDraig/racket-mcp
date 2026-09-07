#lang racket/base
(require rackunit racket/async-channel db mcp)

(for* ([kind '(checkpoint manual idempotent)] [cancel? '(#f #t)])
  (define entered (make-async-channel))
  (define release (make-semaphore 0))
  (define encodings 0)
  (define effects 0)
  (define codec
    (make-value-codec "BlockedInteger" "1" Integer
      (lambda (value)
        (set! encodings (add1 encodings))
        (async-channel-put entered (cons (current-thread) (current-store-connection)))
        (semaphore-wait release)
        value)
      values))
  (define effect? (not (eq? kind 'checkpoint)))
  (define program
    (make-workflow "blocked-codec" "1" "codec-stage-lock"
      (list (workflow-stage 'saved (if effect? 'effect 'checkpoint) codec (lambda (_env) 7)
                            (and effect? 'write) (and effect? kind))
            (workflow-stage 'done 'complete #t
                            (lambda (env) (text-result (number->string (hash-ref env 'saved)))) #f #f))))
  (define adapters
    (if effect?
        (hasheq 'write (effect-adapter kind
          (lambda (_input _key connection)
            (check-false connection)
            (set! effects (add1 effects))
            (committed-result 7 '("effect")))))
        (hasheq)))
  (define tool (make-tool "blocked-codec" '() (lambda (_args) (error 'test "workflow bypassed"))
                          #:workflow program #:execution 'task))
  (define store (open-memory-store))
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
      (define task (call "tools/call" (hasheq 'name "blocked-codec")))
      (define params (hasheq 'taskId (hash-ref task 'taskId)))
      (define entry (sync/timeout 5 entered))
      (check-not-false entry)
      (unless entry (error 'test "encoder did not start"))
      (check-false (cdr entry))
      (define polled (bounded-call "tasks/get" params))
      (check-equal? (and polled (hash-ref polled 'status)) "working")
      (when cancel?
        (check-equal? (bounded-call "tasks/cancel" params) (hasheq 'resultType "complete")))
      (semaphore-post release)
      (check-not-false (sync/timeout 5 (car entry)))
      (check-equal? encodings 1)
      (check-equal? effects (if effect? 1 0))
      (define final (call "tasks/get" params))
      (check-equal? (hash-ref final 'status) (if cancel? "cancelled" "completed"))
      (define task-row (load-instance store (hash-ref task 'taskId)))
      (define flow (load-instance store (hash-ref (stored-instance-state task-row) 'workflow)))
      (define state (stored-instance-state flow))
      (define saved? (or effect? (not cancel?)))
      (check-equal? (hash-ref state 'position) (if saved? 1 0))
      (check-equal? (hash-has-key? (hash-ref state 'values) 'saved) saved?)
      (when saved?
        (check-equal? (decode-value codec (hash-ref (hash-ref state 'values) 'saved)) 7))
      (check-equal? (length (list-instances store #:operation "change-outbox")) (if effect? 1 0))
      (when cancel? (check-false (hash-has-key? state 'result)))
      (unless cancel? (check-equal? (hash-ref final 'result) (text-result "7"))))
    (lambda ()
      (custodian-shutdown-all (runtime-custodian rt))
      (close-store! store))))

;; A transactional effect must keep encoding in the mutation transaction so an
;; invalid representation rolls back application data and the stage/outbox.
(for ([fail? '(#f #t)])
  (define store (open-memory-store))
  (query-exec (state-store-connection store) "CREATE TABLE writes(value INTEGER)")
  (define codec
    (make-value-codec "TransactionalInteger" "1" Integer
      (lambda (value)
        (check-eq? (current-store-connection) (state-store-connection store))
        (if fail? (error 'encoder "invalid representation") value)) values))
  (define program
    (make-workflow "transactional-codec" "1" "codec-stage-lock"
      (list (workflow-stage 'saved 'effect codec (lambda (_env) 7) 'write 'transactional)
            (workflow-stage 'done 'complete #t (lambda (_env) (text-result "done")) #f #f))))
  (define adapters
    (hasheq 'write (effect-adapter 'transactional
      (lambda (value _key connection)
        (check-eq? connection (state-store-connection store))
        (query-exec connection "INSERT INTO writes(value) VALUES (?)" value)
        (committed-result value '("effect"))))))
  (dynamic-wind void
    (lambda ()
      (define (run) (run-workflow program store (hasheq) #:principal "alice" #:adapters adapters))
      (if fail? (check-exn #rx"invalid representation" run) (check-equal? (run) (text-result "done")))
      (check-equal? (query-value (state-store-connection store) "SELECT count(*) FROM writes") (if fail? 0 1))
      (check-equal? (length (list-instances store #:operation "change-outbox")) (if fail? 0 1))
      (define state (stored-instance-state (car (list-instances store #:operation "transactional-codec"))))
      (check-equal? (hash-ref state 'position) (if fail? 0 1))
      (check-equal? (hash-has-key? (hash-ref state 'values) 'saved) (not fail?)))
    (lambda () (close-store! store))))
