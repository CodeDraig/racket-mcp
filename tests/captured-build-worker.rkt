#lang racket/base
(module+ main
  (require racket/path racket/string mcp/json mcp/private/executable-capture)
  (define args (current-command-line-arguments))
  (define application (path->complete-path (vector-ref args 0)))
  (define capture (capture-module-export application 'execute))
  ;; Only fixture bootstrap dependencies receive explicit test identities. Never
  ;; label uncaptured application code as trusted to make this regression pass.
  (define application-directory (path->string (path-only application)))
  (for ([name (in-list (module-code-capture-unobserved capture))])
    (when (string-contains? name application-directory)
      (error 'captured-build-worker "application code was not captured: ~a" name)))
  (unless (equal? (vector-ref args 2) "unsealed")
    (void (seal-module-code-capture! capture
            #:dependencies
            (for/hash ([name (in-list (module-code-capture-unobserved capture))])
              (values name (string-append "explicit-test-bootstrap/1:" (version)))))))
  (write-json ((module-code-capture-value capture) (vector-ref args 1)
               (and (= (vector-length args) 4) (vector-ref args 3))))
  (newline))
