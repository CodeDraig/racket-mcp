#lang racket/base
(require mcp/private/native-executable mcp/private/executable-capture)
;; Do not force the executable identity before the parent replaces its pathname.
(displayln "ready")
(flush-output)
(void (read-line))
(define root (vector-ref (current-command-line-arguments) 0))
(define captured (capture-module-export (string->path root) 'value))
(define explicit
  (for/hash ([name (in-list (module-code-capture-unobserved captured))])
    (values name "same-explicit-runtime-build")))
(write (list (running-executable-identity)
             (seal-module-code-capture! captured #:dependencies explicit)))
(newline)
