#lang racket/base
(require rackunit racket/file racket/port racket/runtime-path racket/tcp
         mcp/private/raco-launcher)
(define-runtime-path manifest "manifest-side-effect.rkt")
(test-case "inspection preserves streams and does not instantiate the application"
  (define out (open-output-string))
  (define err (open-output-string))
  (define status
    (parameterize ([current-input-port (open-input-string "")]
                   [current-output-port out] [current-error-port err])
      (run-command (vector "inspect" (path->string manifest)))))
  (check-equal? status 0)
  (check-regexp-match #rx"example" (get-output-string out))
  (check-equal? (get-output-string err) ""))
(test-case "child failures preserve status and diagnostics"
  (define out (open-output-string))
  (define err (open-output-string))
  (define status
    (parameterize ([current-input-port (open-input-string "")]
                   [current-output-port out] [current-error-port err])
      (run-command (vector "unknown-command" "unused"))))
  (check-not-equal? status 0)
  (check-equal? (get-output-string out) "")
  (check-regexp-match #rx"unknown command" (get-output-string err)))
(test-case "reject malformed arguments before launching"
  (check-exn exn:fail:contract? (lambda () (run-command '("inspect"))))
  (check-exn exn:fail:contract? (lambda () (run-command (vector 42)))))
(test-case "literal path arguments do not undergo shell interpretation"
  (define directory (make-temporary-file "mcp-raco-arguments-~a" 'directory))
  (dynamic-wind void
    (lambda ()
      (define application (build-path directory "literal $name ; argument.rkt"))
      (display-to-file "#lang mcp\n(tool (literal) (text-result \"ok\"))\n" application)
      (define out (open-output-string))
      (parameterize ([current-input-port (open-input-string "")]
                     [current-output-port out])
        (check-equal? (run-command (vector "inspect" (path->string application))) 0))
      (check-regexp-match #rx"literal" (get-output-string out)))
    (lambda () (delete-directory/files directory))))
(test-case "breaking the launcher cleans up its child"
  (define directory (make-temporary-file "mcp-raco-break-~a" 'directory))
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (define application (build-path directory "wait.rkt"))
      (define ready (build-path directory "ready.rktd"))
      (call-with-output-file application
        (lambda (out)
          (fprintf out "#lang mcp\n(require racket/tcp racket/file)\n(define listener (tcp-listen 0 4 #t \"127.0.0.1\"))\n(define-values (host port remote remote-port) (tcp-addresses listener #t))\n(write-to-file port ~s)\n(sync never-evt)\n" (path->string ready))))
      (define broken? #f)
      (define worker
        (parameterize ([current-custodian owner])
          (thread (lambda ()
                    (with-handlers ([exn:break? (lambda (_) (set! broken? #t))])
                      (parameterize ([current-input-port (open-input-string "")]
                                     [current-output-port (open-output-nowhere)]
                                     [current-error-port (open-output-nowhere)])
                        (run-command (vector "serve" (path->string application)))))))))
      (define deadline (+ (current-inexact-milliseconds) 15000))
      (let wait ()
        (unless (file-exists? ready)
          (when (or (thread-dead? worker) (> (current-inexact-milliseconds) deadline))
            (error 'test "child did not acquire its listener"))
          (sync (alarm-evt (+ (current-inexact-milliseconds) 10)))
          (wait)))
      (define port (file->value ready))
      (define-values (in out) (tcp-connect "127.0.0.1" port))
      (close-input-port in) (close-output-port out)
      (break-thread worker)
      (check-not-false (sync/timeout 5 worker))
      (check-true broken?)
      ;; Child termination may finish just after custodian shutdown returns.
      (let wait ()
        (define connected?
          (with-handlers ([exn:fail:network? (lambda (_) #f)])
            (define-values (in out) (tcp-connect "127.0.0.1" port))
            (close-input-port in) (close-output-port out) #t))
        (when connected?
          (when (> (current-inexact-milliseconds) deadline)
            (error 'test "child listener survived launcher cancellation"))
          (sync (alarm-evt (+ (current-inexact-milliseconds) 10)))
          (wait))))
    (lambda () (custodian-shutdown-all owner) (delete-directory/files directory))))
