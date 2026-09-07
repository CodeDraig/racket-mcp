#lang racket/base
(require rackunit racket/file racket/async-channel mcp)
(define path (make-temporary-file "external-changes-~a.sqlite"))
(dynamic-wind void
  (lambda ()
    (for ([store (in-list (list (open-memory-store) (open-sqlite-store path)))])
      (define owner (make-custodian))
      (dynamic-wind void
        (lambda ()
          (define page (external-change-page (list (external-change "one" "alice" '("docs"))) 1))
          (define reads 0)
          (define source (make-external-change-source "database" "1"
            (lambda (cursor limit)
              (check-equal? limit 1000)
              (set! reads (add1 reads)) page) #:initial-cursor 0))
          (check-equal? (external-change-cursor store source) 0)
          (check-equal? (list-instances store) '())
          (define result (reconcile-external-changes! store source))
          (check-equal? (reconciliation-result-recorded result) 1)
          (check-equal? (external-change-cursor store source) 1)
          (define (outbox) (list-instances store #:operation "change-outbox"))
          (check-equal? (length (outbox)) 1)
          (check-equal? (stored-instance-principal (car (outbox))) "alice")
          ;; Repeated event IDs do not create another outbox record.
          (check-equal? (reconciliation-result-recorded (reconcile-external-changes! store source)) 0)
          (check-equal? (length (outbox)) 1)
          ;; Conflict after a new event rolls the whole page back, including its
          ;; outbox and cursor, and cannot move an event to another principal.
          (set! page (external-change-page
            (list (external-change "two" "bob" '("other"))
                  (external-change "one" "bob" '("docs"))) 2))
          (check-exn #rx"event ID reused" (lambda () (reconcile-external-changes! store source)))
          (check-equal? (length (outbox)) 1)
          (check-equal? (external-change-cursor store source) 1)
          (set! page (external-change-page (list (external-change "two" "bob" '("other"))) 2))
          (check-equal? (reconciliation-result-recorded (reconcile-external-changes! store source)) 1)
          (check-equal? (length (outbox)) 2)
          (check-exn #rx"invocation key reused" (lambda () (reconcile-external-changes! store
            (make-external-change-source "database" "2" (lambda args (error 'test "must not fetch")) #:initial-cursor 0))))
          (check-exn #rx"incompatible" (lambda () (external-change-cursor store
            (make-external-change-source "database" "2" (lambda args #f) #:initial-cursor 0))))
          (check-exn #rx"storage transaction" (lambda () (store-transaction store
            (lambda () (reconcile-external-changes! store source)))))
          (set! page (external-change-page (list (external-change "large" "alice" (list (make-string 200 #\x)))) 3))
          (check-exn exn:fail? (lambda () (reconcile-external-changes! store source #:max-bytes 100)))
          (check-equal? (external-change-cursor store source) 2)
          (set! page (external-change-page (list (external-change "invalid" #f '("docs"))) 3))
          (check-exn exn:fail? (lambda () (reconcile-external-changes! store source)))
          (check-equal? (length (outbox)) 2)
          (set! page (external-change-page
            (for/list ([_ (in-range 1001)]) (external-change "too-many" "alice" '("docs"))) 3))
          (check-exn #rx"event limit" (lambda () (reconcile-external-changes! store source)))
          (check-exn #rx"1 MiB" (lambda () (reconcile-external-changes! store source #:max-bytes 1048577)))
          (check-exn #rx"unavailable" (lambda () (reconcile-external-changes! store
            (make-external-change-source "database" "1" (lambda args (error 'feed "unavailable")) #:initial-cursor 0))))
          (check-equal? (external-change-cursor store source) 2)
          ;; Two readers observe the same cursor without holding the store lock.
          ;; Only the winner commits the page; the loser reports supersession.
          (define entered (make-async-channel))
          (define release (make-semaphore 0))
          (define results (make-async-channel))
          (define concurrent-source (make-external-change-source "database" "1"
            (lambda (cursor limit)
              (async-channel-put entered cursor)
              (sync release)
              (external-change-page (list (external-change "three" "alice" '("docs"))) 3)) #:initial-cursor 0))
          (parameterize ([current-custodian owner])
            (for ([_ (in-range 2)])
              (thread (lambda ()
                (async-channel-put results
                  (with-handlers ([(lambda (_) #t) values])
                    (reconcile-external-changes! store concurrent-source)))))))
          (check-equal? (sync/timeout 3 entered) 2)
          (check-equal? (sync/timeout 3 entered) 2)
          (semaphore-post release) (semaphore-post release)
          (define first (sync/timeout 3 results))
          (define second (sync/timeout 3 results))
          (check-true (reconciliation-result? first))
          (check-true (reconciliation-result? second))
          (check-not-equal? (reconciliation-result-status first) (reconciliation-result-status second))
          (check-equal? (+ (reconciliation-result-recorded first) (reconciliation-result-recorded second)) 1)
          (check-equal? (external-change-cursor store source) 3)
          (check-equal? (length (outbox)) 3)
          ;; Publication failure leaves the pending delivery independently
          ;; retryable; it does not move the external cursor backward.
          (check-exn #rx"publication" (lambda () (drain-change-outbox! store (lambda args (error 'publication "interrupted")))))
          (check-equal? (external-change-cursor store source) 3)
          (define delivered '())
          (drain-change-outbox! store (lambda (id principal keys) (set! delivered (cons id delivered))))
          (check-equal? (length delivered) 3)
          (drain-change-outbox! store (lambda args (error 'test "already delivered")))
          (set! page (external-change-page '() #f))
          (check-equal? (reconciliation-result-recorded (reconcile-external-changes! store source)) 0)
          (check-false (external-change-cursor store source)))
        (lambda () (custodian-shutdown-all owner) (close-store! store)))))
  (lambda () (delete-file path)))
