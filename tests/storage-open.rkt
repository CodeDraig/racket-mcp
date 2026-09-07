#lang racket/base
(require rackunit racket/file db mcp/storage)
(define directory (make-temporary-file "mcp-storage-open-~a" 'directory))
(define root (current-custodian))
(define (check-failed-open path predicate [guard (current-security-guard)])
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner] [current-security-guard guard])
        (check-exn predicate (lambda () (open-sqlite-store path))))
      ;; Database connections register with this custodian. Disconnection removes
      ;; that registration; no GC or process-exit cleanup is needed to pass.
      (check-equal? (custodian-managed-list owner root) '()))
    (lambda () (custodian-shutdown-all owner))))
(dynamic-wind void
  (lambda ()
    (define conflict (build-path directory "conflict.sqlite"))
    (define worker-path (string-append (path->string conflict) ".workers"))
    (call-with-output-file worker-path (lambda (out) (display "keep" out)))
    (check-failed-open conflict #rx"not a directory")
    (check-equal? (file->string worker-path) "keep")
    (delete-file worker-path)
    (define recovered (open-sqlite-store conflict))
    (check-true (directory-exists? (state-store-worker-directory recovered)))
    (close-store! recovered)

    (define malformed (build-path directory "malformed.sqlite"))
    (define conn (sqlite3-connect #:database malformed #:mode 'create))
    (query-exec conn "CREATE VIEW journal AS SELECT 1 AS sequence")
    (disconnect conn)
    (check-failed-open malformed exn:fail?)
    ;; Migration failure rolls back any sidecar columns added earlier in the same
    ;; transaction, leaving the existing database available for explicit repair.
    (define inspector (sqlite3-connect #:database malformed))
    (check-false (for/or ([row (in-list (query-rows inspector "PRAGMA table_info(instances)"))])
                   (equal? (vector-ref row 1) "state_marks")))
    (disconnect inspector)

    (define denied (build-path directory "denied.sqlite"))
    (define denied-worker (string->path (string-append (path->string denied) ".workers")))
    (define sentinel (gensym 'setup-failure))
    (define guard
      (make-security-guard (current-security-guard)
        (lambda (_ path modes)
          (when (and path (equal? path denied-worker) (memq 'write modes)) (raise sentinel)))
        (lambda args (void))))
    (check-failed-open denied (lambda (raised) (eq? raised sentinel)) guard)
    (define usable (open-sqlite-store denied))
    (check-true (state-store? usable))
    (close-store! usable))
  (lambda () (delete-directory/files directory)))
