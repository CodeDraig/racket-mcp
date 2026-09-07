#lang racket/base
(require racket/file racket/list mcp)
(provide json-feed-source)
;; The application publishes an append-only JSON array of committed events by
;; atomic file replacement. This reader never writes to the application feed.
(define (json-feed-source name path)
  (make-external-change-source name "1"
    (lambda (cursor limit)
      (define events (string->json (file->string path)))
      (unless (and (list? events) (exact-nonnegative-integer? cursor) (<= cursor (length events)))
        (error 'json-feed-source "feed was truncated or cursor is invalid"))
      (define remaining (drop events cursor))
      (define page (take remaining (min limit (length remaining))))
      (external-change-page
        (for/list ([event page])
          (external-change (hash-ref event 'id) (hash-ref event 'principal) (hash-ref event 'keys)))
        (+ cursor (length page)))) #:initial-cursor 0))
(module+ main
  (define args (current-command-line-arguments))
  (unless (= (vector-length args) 3)
    (error 'external-changes "usage: SOURCE-NAME COMMITTED-FEED.json STATE.sqlite"))
  (define source (json-feed-source (vector-ref args 0) (vector-ref args 1)))
  (define store (open-sqlite-store (vector-ref args 2)))
  (dynamic-wind void
    (lambda ()
      (reconcile-external-changes! store source)
      (drain-change-outbox! store
        (lambda (id principal keys)
          (write-json (hasheq 'outboxId id 'principal principal 'keys keys)) (newline))))
    (lambda () (close-store! store))))
