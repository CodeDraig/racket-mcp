#lang mcp
(module+ test (require rackunit))
(tool (greet [name String])
  (text-result (string-append (request-context-principal (current-request-context)) ": Hello, " name)))

(scenario (stdio-greeting session)
  #:interface mcp-interface
  #:transport 'stdio
  #:principal "reader"
  (define outcome (scenario-call session "tools/call" (hasheq 'name "greet" 'arguments (hasheq 'name "Ada"))))
  (check-equal? (hash-ref (hash-ref outcome 'result) 'content) (list (text-content "reader: Hello, Ada"))))

(scenario (http-greeting session)
  #:interface mcp-interface
  #:transport 'http
  #:principal "reader"
  #:sse? #t
  (define outcome (scenario-call session "tools/call" (hasheq 'name "greet" 'arguments (hasheq 'name "Ada"))))
  (check-equal? (hash-ref (hash-ref outcome 'result) 'content) (list (text-content "reader: Hello, Ada"))))
