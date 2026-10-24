#lang racket/base
(require "../clock.rkt" "../storage.rkt")
(provide (struct-out committed-result) record-committed-change! drain-change-outbox!)
(struct committed-result (result keys) #:transparent)
;; Outbox uses the same SQLite transaction as participating application mutation.
;; Its delivery cursor is durable. A callback must tolerate duplicate delivery
;; after a crash between publication and cursor advancement.
(define (record-committed-change! store principal keys)
  (create-instance! store principal "change-outbox" (hasheq 'keys keys) "1" "outbox-v1" (+ (mcp-current-seconds) 31536000)
                    (hasheq 'status "pending")))
(define (drain-change-outbox! store deliver)
  (for ([instance (in-list (list-instances store #:operation "change-outbox"))])
    (when (equal? (hash-ref (stored-instance-state instance) 'status) "pending")
      (deliver (stored-instance-handle instance) (stored-instance-principal instance) (hash-ref (stored-instance-arguments instance) 'keys))
      (store-transaction store (lambda () (define current (load-instance store (stored-instance-handle instance)))
                                (update-instance! store current (hasheq 'status "delivered")))))))
