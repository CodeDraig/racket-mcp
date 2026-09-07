#lang racket/base
(require racket/file racket/list mcp)
(module+ main
  (define args (current-command-line-arguments))
  (define store (open-sqlite-store (vector-ref args 0)))
  (define feed (vector-ref args 1))
  (define delivered (vector-ref args 2))
  (define mode (vector-ref args 3))
  (define source
    (make-external-change-source "external-database" "1"
      (lambda (cursor limit)
        (when (equal? mode "read-crash") (exit 16))
        (define remaining (drop (string->json (file->string feed)) cursor))
        (define page (take remaining (min limit (length remaining))))
        (external-change-page
          (for/list ([event page])
            (external-change (hash-ref event 'id) (hash-ref event 'principal) (hash-ref event 'keys)))
          (+ cursor (length page)))) #:initial-cursor 0))
  (cond
    [(member mode '("record" "read-crash"))
     (reconcile-external-changes! store source)
     ;; Process termination after the commit, before any outbox delivery.
     (exit 17)]
    [else
     (drain-change-outbox! store
       (lambda (id principal keys)
         (call-with-output-file delivered #:exists 'append
           (lambda (out) (write-json (hasheq 'id id 'principal principal 'keys keys) out) (newline out)))
         ;; Delivery occurred, but the SDK has not advanced the outbox status.
         (when (equal? mode "deliver-crash") (exit 18))))
     (close-store! store)]))
