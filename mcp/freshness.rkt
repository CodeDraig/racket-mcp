#lang racket/base
(require racket/list racket/set "storage.rkt" "json.rkt")
(provide cache-clock (struct-out cache-partition) make-resource-cache cache-ref! invalidate-keys! (struct-out committed-result)
         record-committed-change! drain-change-outbox!)
(struct cache-partition (owner authority) #:transparent)
(struct cache-entry (value expires dependencies) #:transparent)
(struct resource-cache (lock entries clock generation limit) #:mutable #:transparent)
(struct committed-result (result keys) #:transparent)
(define (make-resource-cache #:clock [clock current-inexact-milliseconds] #:limit [limit 1024])
  (unless (exact-positive-integer? limit) (raise-argument-error 'make-resource-cache "exact-positive-integer?" limit))
  (resource-cache (make-semaphore 1) (make-hash) clock 0 limit))
(define (cache-clock cache) ((resource-cache-clock cache)))
(define (cache-ref! cache principal identity dependencies ttl compute
                    #:usable? [usable? (lambda (_) #t)] #:cacheable? [cacheable? (lambda (_) #t)]
                    #:on-hit [on-hit (lambda (value remaining) value)] #:on-invalidated [on-invalidated values]
                    #:expires-at [expires-at #f])
  (define key (cons principal identity))
  (define-values (hit generation)
    (call-with-semaphore (resource-cache-lock cache)
      (lambda ()
        (define old (hash-ref (resource-cache-entries cache) key #f))
        (values (and old (> (cache-entry-expires old) ((resource-cache-clock cache))) old)
                (resource-cache-generation cache)))))
  (cond [(and hit (usable? (cache-entry-value hit)))
         (define value (on-hit (cache-entry-value hit)
                              (max 0 (inexact->exact (floor (- (cache-entry-expires hit) ((resource-cache-clock cache))))))))
         (if (call-with-semaphore (resource-cache-lock cache) (lambda () (= generation (resource-cache-generation cache))))
             value (on-invalidated value))]
        [else
         ;; Application computation may re-enter the cache or commit a change.
         ;; If invalidation intervenes, return the observed value without caching it.
         (define value (compute))
         (define lifetime (if (procedure? ttl) (ttl value) ttl))
         (define expiration (if expires-at (expires-at value) (+ ((resource-cache-clock cache)) lifetime)))
         (define keys (if (procedure? dependencies) (dependencies value) dependencies))
         (define cacheable (cacheable? value))
         (define current?
           (call-with-semaphore (resource-cache-lock cache)
             (lambda ()
               (define unchanged? (= generation (resource-cache-generation cache)))
               (when (and unchanged? cacheable (positive? lifetime))
                 (when (>= (hash-count (resource-cache-entries cache)) (resource-cache-limit cache))
                   (hash-remove! (resource-cache-entries cache) (car (hash-keys (resource-cache-entries cache)))))
                 (hash-set! (resource-cache-entries cache) key
                            (cache-entry value expiration (list->set keys))))
               unchanged?)))
         (if current? value (on-invalidated value))]))
(define (invalidate-keys! cache keys #:principal [principal #f])
  (call-with-semaphore (resource-cache-lock cache)
    (lambda ()
      (set-resource-cache-generation! cache (add1 (resource-cache-generation cache)))
      (define affected (for/list ([(key entry) (in-hash (resource-cache-entries cache))]
                                  #:when (and (or (not principal) (equal? principal (if (cache-partition? (car key)) (cache-partition-owner (car key)) (car key))))
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
