#lang racket/base
(require rackunit racket/async-channel mcp/subscription mcp/error)
(define h (make-subscription-hub #:limit 2))
(define filter (hasheq 'toolsListChanged #t 'resourceSubscriptions '("file:///item")))
(define entered (make-semaphore 0))
(define release (make-semaphore 0))
(define slow-events (make-async-channel))
(define slow-result (make-async-channel))
(define slow
  (thread (lambda ()
    (with-handlers ([exn:fail? (lambda (e) (async-channel-put slow-result e))])
      (async-channel-put slow-result
        (listen-subscription h 1 "slow" filter
          (lambda (message)
            (when (equal? (hash-ref message 'method) "notifications/subscriptions/acknowledged")
              (semaphore-post entered) (semaphore-wait release))
            (async-channel-put slow-events message))))))))
(check-not-false (sync/timeout 2 entered))
(define healthy-events (make-async-channel))
(define healthy-result (make-async-channel))
(define healthy
  (thread (lambda ()
    (async-channel-put healthy-result
      (listen-subscription h 2 "healthy" filter
        (lambda (message) (async-channel-put healthy-events message)))))))
(define ack (sync/timeout 2 healthy-events))
(check-not-false ack)
(check-equal? (hash-ref ack 'method) "notifications/subscriptions/acknowledged")
;; Each publication completes while the first listener is still stuck in ack I/O.
(for ([i (in-range 3)])
  (define publisher (thread (lambda () (publish-change! h "notifications/tools/list_changed" (hasheq 'revision i)))))
  (check-not-false (sync/timeout 2 (thread-dead-evt publisher)))
  (define event (sync/timeout 2 healthy-events))
  (check-equal? (hash-ref event 'method) "notifications/tools/list_changed")
  (check-equal? (hash-ref (hash-ref event 'params) 'revision) i))
(check-false (sync/timeout 0 slow-events))
(semaphore-post release)
(define slow-ack (sync/timeout 2 slow-events))
(check-equal? (hash-ref slow-ack 'method) "notifications/subscriptions/acknowledged")
(define overflow (sync/timeout 2 slow-result))
(check-true (exn:fail:mcp? overflow))
(check-equal? (exn:fail:mcp-code overflow) -32000)
(check-false (sync/timeout 0 slow-events))
(check-equal? (subscription-resource-targets h) '(("healthy" . "file:///item")))
(close-subscriptions! h)
(check-equal? (hash-ref (sync/timeout 2 healthy-result) 'resultType) "complete")
(thread-wait slow) (thread-wait healthy)
(check-equal? (subscription-resource-targets h) '())

;; A failed acknowledgement runs deregistration even for a non-exception raise.
(check-exn (lambda (value) (eq? value 'failed-ack))
  (lambda () (listen-subscription h 3 "failed" filter (lambda (_) (raise 'failed-ack)))))
(check-equal? (subscription-resource-targets h) '())

;; Forced termination during acknowledgement must not leave a live subscription.
(define stuck (make-semaphore 0))
(define killed
  (thread (lambda ()
    (listen-subscription h 4 "killed" filter
      (lambda (_) (semaphore-post stuck) (sync never-evt))))))
(check-not-false (sync/timeout 2 stuck))
(kill-thread killed)
(thread-wait killed)
(check-equal? (subscription-resource-targets h) '())
(check-exn exn:fail:contract? (lambda () (make-subscription-hub #:limit 0)))

;; A change queued during acknowledgement is retained when capacity suffices.
(define ack-started (make-semaphore 0))
(define ack-release (make-semaphore 0))
(define events (make-async-channel))
(define completed (make-async-channel))
(define queued
  (thread (lambda ()
    (async-channel-put completed
      (listen-subscription h 5 "queued" filter
        (lambda (message)
          (when (equal? (hash-ref message 'method) "notifications/subscriptions/acknowledged")
            (semaphore-post ack-started) (semaphore-wait ack-release))
          (async-channel-put events message)))))))
(check-not-false (sync/timeout 2 ack-started))
(publish-change! h "notifications/tools/list_changed" (hasheq 'revision 10))
(check-false (sync/timeout 0 events))
(semaphore-post ack-release)
(check-equal? (hash-ref (sync/timeout 2 events) 'method) "notifications/subscriptions/acknowledged")
(check-equal? (hash-ref (hash-ref (sync/timeout 2 events) 'params) 'revision) 10)
(close-subscriptions! h)
(check-equal? (hash-ref (sync/timeout 2 completed) 'resultType) "complete")
(thread-wait queued)
