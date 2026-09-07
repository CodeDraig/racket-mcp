#lang racket/base
(require "freshness.rkt" "json.rkt" "storage.rkt")
(provide (struct-out external-change) (struct-out external-change-page)
         (struct-out external-change-source) (struct-out reconciliation-result)
         make-external-change-source reconcile-external-changes! external-change-cursor)

;; The reader observes an application's durable committed-change feed. It never
;; receives a mutation callback. Credentials and reader procedures stay in memory.
(struct external-change (id principal keys) #:transparent)
(struct external-change-page (events cursor) #:transparent)
(struct external-change-source (name version reader initial-cursor) #:transparent)
(struct reconciliation-result (status recorded cursor) #:transparent)
(define metadata-owner "mcp:external-change-feed")
(define metadata-expiry 9223372036854775807)
(define (nonempty-string? value) (and (string? value) (positive? (string-length value))))
(define (check-source! source)
  (unless (and (external-change-source? source)
               (nonempty-string? (external-change-source-name source))
               (nonempty-string? (external-change-source-version source))
               (procedure? (external-change-source-reader source))
               (procedure-arity-includes? (external-change-source-reader source) 2)
               (json-value? (external-change-source-initial-cursor source)))
    (raise-argument-error 'external-change-source "named/versioned source with binary reader and JSON cursor" source)))
(define (make-external-change-source name version reader #:initial-cursor [cursor json-null])
  (define source (external-change-source name version reader cursor))
  (check-source! source)
  (struct-copy external-change-source source
    [name (string->immutable-string name)] [version (string->immutable-string version)]
    [initial-cursor (string->json (json->string cursor))]))
(define (source-instance! store source)
  (check-source! source)
  (create-instance! store metadata-owner "external-change-source"
    (hasheq 'name (external-change-source-name source) 'version (external-change-source-version source)
            'initialCursor (external-change-source-initial-cursor source))
    "1" "external-change-source/1" metadata-expiry
    (hasheq 'cursor (external-change-source-initial-cursor source))
    #:key (external-change-source-name source)))
(define (external-change-cursor store source)
  (check-source! source)
  (define existing (find-instance-by-key store metadata-owner "external-change-source" (external-change-source-name source)))
  (when existing
    (unless (equal? (stored-instance-arguments existing)
                    (hasheq 'name (external-change-source-name source) 'version (external-change-source-version source)
                            'initialCursor (external-change-source-initial-cursor source)))
      (error 'external-change-cursor "source configuration is incompatible with the saved cursor")))
  (if existing (hash-ref (stored-instance-state existing) 'cursor)
      (string->json (json->string (external-change-source-initial-cursor source)))))
(define (snapshot-page page event-limit byte-limit)
  (unless (and (external-change-page? page)
               (list? (external-change-page-events page))
               (<= (length (external-change-page-events page)) event-limit))
    (error 'reconcile-external-changes! "reader must return a page within the event limit"))
  (define events
    (for/list ([event (in-list (external-change-page-events page))])
      (unless (and (external-change? event) (nonempty-string? (external-change-id event))
                   (nonempty-string? (external-change-principal event))
                   (list? (external-change-keys event)) (json-value? (external-change-keys event)))
        (error 'reconcile-external-changes! "invalid committed event identity, principal, or dependency keys"))
      (hasheq 'id (external-change-id event) 'principal (external-change-principal event)
              'keys (external-change-keys event))))
  ;; Encoding and decoding snapshots mutable adapter-owned values before any
  ;; event/outbox/cursor write. The decoder enforces the configured byte bound.
  (string->json (json->string (hasheq 'events events 'cursor (external-change-page-cursor page)))
                #:max-bytes byte-limit))
(define (reconcile-external-changes! store source #:max-events [event-limit 1000] #:max-bytes [byte-limit 1048576])
  (unless (exact-positive-integer? event-limit)
    (raise-argument-error 'reconcile-external-changes! "positive exact event limit" event-limit))
  (unless (and (exact-positive-integer? byte-limit) (<= byte-limit 1048576))
    (raise-argument-error 'reconcile-external-changes! "positive exact byte limit no greater than the 1 MiB storage limit" byte-limit))
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'reconcile-external-changes! "external feed reads must not hold a storage transaction"))
  (define before (source-instance! store source))
  (define cursor (hash-ref (stored-instance-state before) 'cursor))
  (define page
    (snapshot-page ((external-change-source-reader source)
                    (string->json (json->string cursor)) event-limit)
                   event-limit byte-limit))
  (store-transaction store
    (lambda ()
      (define current (load-instance store (stored-instance-handle before)))
      (cond
        [(not (= (stored-instance-revision before) (stored-instance-revision current)))
         (reconciliation-result 'superseded 0 (hash-ref (stored-instance-state current) 'cursor))]
        [else
         (define operation (string-append "external-change-event:" (stored-instance-handle current)))
         (define recorded
           (for/sum ([event (in-list (hash-ref page 'events))])
             (define id (hash-ref event 'id))
             (define existing (find-instance-by-key store metadata-owner operation id))
             (cond
               [existing
                (unless (equal? event (stored-instance-arguments existing))
                  (error 'reconcile-external-changes! "external event ID reused with different principal or keys: ~a" id))
                0]
               [else
                (define keys (hash-ref event 'keys))
                (define outbox (and (pair? keys) (record-committed-change! store (hash-ref event 'principal) keys)))
                (create-instance! store metadata-owner operation event "1" "external-change-event/1"
                  metadata-expiry (hasheq 'outbox (or (and outbox (stored-instance-handle outbox)) #f)) #:key id)
                1])))
         (define next (hash-ref page 'cursor))
         (unless (and (zero? recorded) (equal? next cursor))
           (update-instance! store current (hasheq 'cursor next))
           (record-event! store (stored-instance-handle current)
             (hasheq 'kind "external-changes-reconciled" 'recorded recorded 'cursor next)))
         (reconciliation-result 'recorded recorded next)]))))
