#lang racket/base
(require rackunit racket/port racket/runtime-path)
(define-runtime-path example "../examples/greeter.rkt")
(define-runtime-path uninstantiated "manifest-side-effect.rkt")
(define namespace (make-base-namespace))
(parameterize ([current-namespace namespace])
  (check-false (module-declared? 'mcp/runtime #f))
  (define entry (dynamic-require 'mcp/command 'main))
  (check-true (procedure? entry))
  (for ([module '(mcp/runtime mcp/cli mcp/descriptor mcp/lang)])
    (check-false (module-declared? module #f)))
  ;; Invocation, unlike importing the entry, starts the normal SDK command path.
  (define output
    (parameterize ([current-command-line-arguments (vector "inspect" (path->string example))])
      (with-output-to-string entry)))
  (check-true (module-declared? 'mcp/cli #f))
  (check-true (module-declared? 'mcp/runtime #f))
  (check-regexp-match #rx"greeter" output)
  (check-regexp-match #rx"greet" output)
  (define original
    (parameterize ([current-command-line-arguments (vector "inspect" (path->string example))])
      (with-output-to-string (dynamic-require 'mcp/cli 'main))))
  (check-equal? output original)
  (define manifest-output
    (parameterize ([current-command-line-arguments (vector "inspect" (path->string uninstantiated))])
      (with-output-to-string entry)))
  (check-regexp-match #rx"example" manifest-output))
