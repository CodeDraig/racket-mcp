#lang racket/base
(require rackunit racket/file racket/list racket/port db mcp)
(define dir (make-temporary-file "mcp-workflow-changes-~a" 'directory (current-directory)))
(define path (build-path dir "state.sqlite"))
(define store (open-sqlite-store path))
(define changes-called 0)
(workflow (edit [id String]) #:version "1"
  #:changes [outcome (begin (set! changes-called (add1 changes-called)) (list (string-append "complete:" id)))]
  (perform [saved String] #:adapter writer #:policy transactional id)
  (await-input [answer Any] (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
  (text-result saved))
(define program (tool-descriptor-workflow edit))
(define adapters
  (hasheq 'writer (effect-adapter 'transactional
    (lambda (input key connection)
      (query-exec connection "INSERT INTO writes(value) VALUES (?)" input)
      (committed-result input (list (string-append "effect:" input)))))))
(query-exec (state-store-connection store) "CREATE TABLE writes(value TEXT)")
(define (outbox) (list-instances store #:operation "change-outbox"))
(dynamic-wind void
  (lambda ()
    (check-exn #rx"own its storage transaction"
      (lambda () (store-transaction store (lambda () (run-workflow program store (hasheq 'id "nested") #:principal "alice" #:adapters adapters)))))
    (define first (run-workflow program store (hasheq 'id "1") #:principal "alice" #:adapters adapters))
    (check-equal? (hash-ref first 'resultType) "input_required")
    (check-equal? (query-value (state-store-connection store) "SELECT count(*) FROM writes") 1)
    (check-equal? (map (lambda (i) (hash-ref (stored-instance-arguments i) 'keys)) (outbox)) '(("effect:1")))
    (define token (hash-ref first 'requestState))
    (close-store! store) (set! store (open-sqlite-store path))
    (define completed
      (parameterize ([current-workflow-change-publisher (lambda () (error 'publication "offline"))]
                     [current-error-port (open-output-string)])
        (run-workflow program store (hasheq 'id "1") #:principal "alice" #:state token
                      #:responses (hasheq 'answer (hasheq 'action "decline")) #:adapters adapters)))
    (check-equal? (hash-ref completed 'resultType) "complete")
    (check-equal? changes-called 1)
    (check-equal? (length (outbox)) 2)
    (close-store! store) (set! store (open-sqlite-store path))
    (define workers
      (for/list ([i (in-range 5)])
        (thread (lambda ()
          (check-equal? (run-workflow program store (hasheq 'id "1") #:principal "alice" #:state token #:adapters adapters) completed)))))
    (for-each thread-wait workers)
    (check-equal? changes-called 1)
    (check-equal? (length (outbox)) 2)
    (define delivered '())
    (drain-change-outbox! store (lambda (_id owner keys) (check-equal? owner "alice") (set! delivered (append keys delivered))))
    (check-equal? (sort delivered string<?) '("complete:1" "effect:1"))
    (drain-change-outbox! store (lambda args (error 'test "duplicate publication")))
    ;; Mutation and outbox must both roll back when an acknowledged value violates
    ;; the stage contract, before a transactional effect can advance.
    (define bad-adapters
      (hasheq 'writer (effect-adapter 'transactional
        (lambda (input key connection)
          (query-exec connection "INSERT INTO writes(value) VALUES (?)" input)
          (committed-result 42 '("bad"))))))
    (check-exn exn:fail? (lambda () (run-workflow program store (hasheq 'id "2") #:principal "alice" #:adapters bad-adapters)))
    (check-equal? (query-value (state-store-connection store) "SELECT count(*) FROM writes") 1)
    (check-equal? (length (outbox)) 2)
    (workflow (repairable) #:version "1" #:key (lambda (_) "one")
      (perform [receipt Integer] #:adapter external #:policy manual 0)
      (text-result (number->string receipt)))
    (define manual-program (tool-descriptor-workflow repairable))
    (check-exn exn:fail? (lambda () (run-workflow manual-program store (hasheq) #:principal "alice"
      #:adapters (hasheq 'external (effect-adapter 'manual (lambda args (error 'external "uncertain")))))))
    (define repair-instance (find-instance-by-key store "alice" "repairable" "one"))
    (void (recover-workflow! store (stored-instance-handle repair-instance) 'receipt 'outcome
                            #:principal "alice" #:outcome (committed-result 42 '("repair"))))
    (check-equal? (length (outbox)) 3)
    (check-equal? (hash-ref (run-workflow manual-program store (hasheq) #:principal "alice") 'content)
                  (list (text-content "42")))
    (check-equal? (length (outbox)) 3)
    ;; A completion error does not evaluate a completion change declaration.
    (workflow (unsuccessful) #:version "1" #:changes [outcome (error 'test "failed completion emitted changes")]
      (error-result "failed"))
    (check-true (hash-ref (run-workflow (tool-descriptor-workflow unsuccessful) store (hasheq) #:principal "alice") 'isError)))
  (lambda () (close-store! store) (delete-directory/files dir)))
