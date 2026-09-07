#lang racket/base
(require racket/list racket/set "storage.rkt" "json.rkt")
(provide make-resource-cache cache-ref! invalidate-keys! (struct-out committed-result)
         record-committed-change! drain-change-outbox!)
(struct cache-entry (value expires dependencies) #:transparent)
(struct resource-cache (lock entries clock) #:transparent)
(struct committed-result (result keys) #:transparent)
(define (make-resource-cache #:clock [clock current-inexact-milliseconds]) (resource-cache (make-semaphore 1) (make-hash) clock))
(define (cache-ref! cache principal identity dependencies ttl compute)
  ;; Computing under this lock prevents invalidation racing a stale insertion.
  ;; A future per-key loader can reduce contention without changing that order.
  (call-with-semaphore (resource-cache-lock cache)
    (lambda ()
      (define key (cons principal identity)) (define now ((resource-cache-clock cache)))
      (define old (hash-ref (resource-cache-entries cache) key #f))
      (cond [(and old (> (cache-entry-expires old) now)) (cache-entry-value old)]
            [else (define value (compute))
                  (when (positive? ttl) (hash-set! (resource-cache-entries cache) key (cache-entry value (+ now ttl) (list->set dependencies)))) value]))))
(define (invalidate-keys! cache keys #:principal [principal #f])
  (call-with-semaphore (resource-cache-lock cache)
    (lambda ()
      (define affected (for/list ([(key entry) (in-hash (resource-cache-entries cache))]
                                  #:when (and (or (not principal) (equal? principal (car key)))
                                              (not (set-empty? (set-intersect (list->set keys) (cache-entry-dependencies entry)))))) key))
      (for ([key (in-list affected)]) (hash-remove! (resource-cache-entries cache) key))
      (map cdr affected))))
;; Outbox uses the same SQLite transaction as participating application mutation.
;; Its delivery cursor is durable. A callback must tolerate duplicate delivery
;; after a crash between publication and cursor advancement.
(define (record-committed-change! store principal keys)
  (create-instance! store principal "change-outbox" (hasheq 'keys keys) "1" "outbox-v1" (+ (current-seconds) 31536000)
                    (hasheq 'status "pending")))
(define (drain-change-outbox! store deliver)
  (for ([instance (in-list (list-instances store #:operation "change-outbox"))])
    (when (equal? (hash-ref (stored-instance-state instance) 'status) "pending")
      (deliver (stored-instance-handle instance) (stored-instance-principal instance) (hash-ref (stored-instance-arguments instance) 'keys))
      (store-transaction store (lambda () (define current (load-instance store (stored-instance-handle instance)))
                                (update-instance! store current (hasheq 'status "delivered")))))))
