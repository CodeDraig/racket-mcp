#lang racket/base
(require rackunit racket/async-channel racket/list mcp)

(for ([mode '(success encoder-failure stale)])
  (define entered (make-async-channel))
  (define release (make-semaphore 0))
  (define calls 0)
  (define owner (make-custodian))
  (define store (open-memory-store))
  (define codec
    (make-value-codec "ObservedInteger" "1" Integer
      (lambda (value)
        (set! calls (add1 calls))
        (async-channel-put entered (current-store-connection))
        (semaphore-wait release)
        (when (eq? mode 'encoder-failure) (error 'encoder "observed encoding failed"))
        value) values))
  (define registry (make-codec-registry (list codec)))
  (define program
    (make-workflow "recover-codec" "1" "recovery-codec-lock"
      (list (workflow-stage 'effect 'effect codec (lambda (_env) 1) 'write 'manual)
            (workflow-stage 'done 'complete #t (lambda (_env) (text-result "done")) #f #f))))
  (define adapters (hasheq 'write (effect-adapter 'manual (lambda args (error 'adapter "uncertain")))))
  (define (launch thunk)
    (define answers (make-async-channel))
    (parameterize ([current-custodian owner])
      (thread (lambda () (async-channel-put answers (with-handlers ([exn:fail? values]) (thunk))))))
    answers)
  (dynamic-wind void
    (lambda ()
      (check-exn #rx"uncertain" (lambda () (run-workflow program store (hasheq) #:principal "alice" #:adapters adapters)))
      (define original (car (list-instances store #:operation "recover-codec")))
      (define id (stored-instance-handle original))
      (define (repair [principal "alice"])
        (recover-workflow! store id 'effect 'outcome #:principal principal
                           #:outcome (committed-result 9 '("observed")) #:codecs registry))
      (check-exn #rx"foreign handle" (lambda () (repair "bob")))
      (check-exn #rx"own its storage transaction" (lambda () (store-transaction store repair)))
      (check-equal? calls 0)
      (define completed (launch repair))
      ;; Box the event result: #f is the expected connection, not a timeout.
      (define connection (sync/timeout 5 (wrap-evt entered box)))
      (check-not-false connection)
      (unless connection (error 'test "recovery encoder did not start"))
      (check-false (unbox connection))
      (define polled (sync/timeout 2 (launch (lambda () (load-instance store id)))))
      (check-equal? polled original)
      (define competing (sync/timeout 2 (launch (lambda () (recover-workflow! store id 'effect 'abandon #:principal "alice")))))
      (check-true (exn:fail? competing))
      (when (exn:fail? competing) (check-regexp-match #rx"execution is active" (exn-message competing)))
      (define before
        (if (eq? mode 'stale)
            (update-instance! store original (hash-set (stored-instance-state original) 'diagnostic "changed"))
            original))
      (semaphore-post release)
      (define outcome (sync/timeout 5 completed))
      (check-not-false outcome)
      (check-equal? calls 1)
      (define current (load-instance store id))
      (define repairs (filter (lambda (event) (equal? (hash-ref event 'kind) "recovery")) (instance-events store id)))
      (cond
        [(eq? mode 'success)
         (check-true (stored-instance? outcome))
         (check-equal? (hash-ref (stored-instance-state current) 'position) 1)
         (check-equal? (decode-value codec (hash-ref (hash-ref (stored-instance-state current) 'values) 'effect)) 9)
         (check-equal? (length repairs) 1)
         (check-equal? (length (list-instances store #:operation "change-outbox")) 1)]
        [else
         (check-true (exn:fail? outcome))
         (when (exn:fail? outcome)
           (check-regexp-match (if (eq? mode 'stale) #rx"concurrent state transition" #rx"observed encoding failed") (exn-message outcome)))
         (check-equal? current before)
         (check-equal? repairs '())
         (check-equal? (list-instances store #:operation "change-outbox") '())
         ;; Failed encoding/CAS releases the claim for a later explicit repair.
         (define replacement-codec (make-value-codec "ObservedInteger" "1" Integer values values))
         (check-true (stored-instance?
           (recover-workflow! store id 'effect 'outcome #:principal "alice" #:outcome 9
                              #:codecs (make-codec-registry (list replacement-codec)))))]))
    (lambda () (custodian-shutdown-all owner) (close-store! store))))
