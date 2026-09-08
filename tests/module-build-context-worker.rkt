#lang racket/base
(module+ main
  (require racket/path racket/string mcp/json mcp/private/executable-capture mcp/private/module-build-context)
  (define args (current-command-line-arguments))
  (define application (path->complete-path (vector-ref args 0)))
  (define context (dynamic-require application 'ctx))
  (define capture (module-build-context-capture context))
  ;; Only fixture bootstrap dependencies receive explicit test identities. Never
  ;; label uncaptured application code as trusted to make this regression pass.
  (define application-directory (path->string (path-only application)))
  (for ([name (in-list (module-code-capture-unobserved capture))])
    (when (string-contains? name application-directory)
      (error 'module-build-context-worker "application code was not captured: ~a" name)))
  (unless (equal? (vector-ref args 2) "unsealed")
    (void (seal-module-build-context! context
            #:dependencies
            (for/hash ([name (in-list (module-code-capture-unobserved capture))])
              (values name (string-append "explicit-test-bootstrap/1:" (version)))))))
  (write-json ((dynamic-require application 'execute) (vector-ref args 1)
               (and (= (vector-length args) 4) (vector-ref args 3))))
  (newline))
