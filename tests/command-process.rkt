#lang racket/base
(require rackunit racket/runtime-path mcp/scenario mcp/json)
(define-runtime-path example "../examples/greeter.rkt")
(call-with-scenario-process
  (list (find-executable-path "racket") "-l" "mcp/command" "--" "serve" example)
  (lambda (session)
    (define outcome (scenario-process-call session "tools/call"
      (hasheq 'name "greet" 'arguments (hasheq 'name "Ada"))))
    (check-equal? (hash-ref (hash-ref outcome 'result) 'resultType) "complete")
    (check-equal? (hash-ref (hash-ref outcome 'result) 'content)
                  (list (hasheq 'type "text" 'text "Hello, Ada")))))
