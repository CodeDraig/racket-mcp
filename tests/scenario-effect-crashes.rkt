#lang racket/base
(require db rackunit racket/file racket/list racket/runtime-path mcp mcp/scenario)
(define-runtime-path fixture "effect-crash-server.rkt")
(define root (make-temporary-file "scenario-effect-crashes-~a" 'directory))
(define (await-file path)
  (define deadline (+ (current-inexact-monotonic-milliseconds) 10000))
  (let loop ()
    (unless (file-exists? path)
      (when (> (current-inexact-monotonic-milliseconds) deadline)
        (error 'effect-crash "server did not reach the authored crash boundary"))
      (sleep 0.01) (loop))))
(define (mutation-count directory policy)
  (define c (sqlite3-connect #:database (build-path directory
                            (if (eq? policy 'transactional) "state.sqlite" "application.sqlite")) #:mode 'read-only))
  (dynamic-wind void (lambda () (query-value c "SELECT count(*) FROM mutations")) (lambda () (disconnect c))))
(dynamic-wind void
  (lambda ()
    (for* ([transport '(stdio http)] [policy '(transactional idempotent manual)] [boundary '("before" "after" "recorded")])
      (test-case (format "~a ~a effect crash boundary: ~a" transport policy boundary)
        (define directory (build-path root (format "~a-~a-~a" transport policy boundary)))
        (make-directory directory)
        (call-with-scenario-process
          (list (find-executable-path "racket") fixture directory (symbol->string policy) boundary (symbol->string transport))
          (lambda (session)
            (define initial-response (scenario-process-call session "tools/call" (hasheq 'name "mutate")))
            (check-true (hash-has-key? initial-response 'result) (format "initial: ~s" initial-response))
            (define initial (hash-ref initial-response 'result))
            (check-equal? (hash-ref initial 'resultType) "input_required")
            (define resume (hasheq 'name "mutate" 'requestState (hash-ref initial 'requestState)
                                   'inputResponses (hasheq 'answer (hasheq 'action "accept" 'content (hasheq 'ok #t)))))
            (define interrupted (scenario-process-request session "tools/call" resume #:timeout #f))
            (await-file (build-path directory "ready"))
            (scenario-process-kill! session)
            (define lost (sync/timeout 2 interrupted))
            (check-true (exn? lost))
            (define recorded? (equal? boundary "recorded"))
            (define committed? (or recorded? (and (not (eq? policy 'transactional)) (equal? boundary "after"))))
            (check-equal? (mutation-count directory policy) (if committed? 1 0))
            (when recorded?
              ;; Verify the durable stage boundary independently of the child's
              ;; signal and the eventual wire response.
              (define store (open-sqlite-store (build-path directory "state.sqlite")))
              (dynamic-wind void
                (lambda ()
                  (define state (stored-instance-state (car (list-instances store #:operation "mutate"))))
                  (check-equal? (hash-ref state 'position) 3)
                  (check-equal? (hash-ref (hash-ref state 'values) 'written) 7)
                  (check-false (hash-has-key? state 'result)))
                (lambda () (close-store! store))))
            (display-to-file "continue" (build-path directory "release"))
            (scenario-process-restart! session)
            (when (and (eq? policy 'manual) (not recorded?))
              ;; Before/after mutation are uncertain; a recorded result is not.
              (define uncertain (scenario-process-call session "tools/call" resume))
              (check-true (hash-has-key? uncertain 'error))
              (check-equal? (length (file->lines (build-path directory "attempts"))) 1)
              (scenario-process-kill! session)
              (define store (open-sqlite-store (build-path directory "state.sqlite")))
              (dynamic-wind void
                (lambda ()
                  (define instance (car (list-instances store #:operation "mutate")))
                  (if committed?
                      (recover-workflow! store (stored-instance-handle instance) 'written 'outcome
                        #:principal (stored-instance-principal instance) #:outcome 7)
                      (recover-workflow! store (stored-instance-handle instance) 'written 'retry
                        #:principal (stored-instance-principal instance))))
                (lambda () (close-store! store)))
              (scenario-process-restart! session))
            (define completed
              (if recorded?
                  (let ([one (scenario-process-request session "tools/call" resume)]
                        [two (scenario-process-request session "tools/call" resume)])
                    ;; Fresh request IDs may race on the same durable continuation.
                    (define first (sync/timeout 10 one))
                    (define second (sync/timeout 10 two))
                    (check-true (hash? first))
                    (check-true (hash? second))
                    (check-not-equal? (hash-ref first 'id) (hash-ref second 'id))
                    (check-equal? (hash-ref first 'result) (hash-ref second 'result))
                    first)
                  (scenario-process-call session "tools/call" resume)))
            (check-true (hash-has-key? completed 'result) (format "resumed: ~s" completed))
            (check-equal? (hash-ref (hash-ref completed 'result) 'structuredContent) (hasheq 'value 7))
            ;; Terminal retries, including another process generation, cannot mutate again.
            (scenario-process-restart! session)
            (check-equal? (hash-ref (scenario-process-call session "tools/call" resume) 'result) (hash-ref completed 'result))
            (check-eq? (sync/timeout 0 interrupted) lost)
            (check-equal? (mutation-count directory policy) 1)
            (check-equal? (file->lines (build-path directory "checkpoints")) '("checkpoint"))
            (define attempts (file->lines (build-path directory "attempts")))
            (check-equal? (length attempts) (if (or recorded? (and (eq? policy 'manual) committed?)) 1 2))
            ;; Transactional recovery rolls back the mutation; only recorded
            ;; external intents promise the same adapter key across retries.
            (unless (eq? policy 'transactional)
              (check-equal? (length (remove-duplicates attempts)) 1)))
          #:transport transport #:capabilities (hasheq 'elicitation (hasheq)) #:shutdown-timeout 0.2))))
  (lambda () (delete-directory/files root)))
