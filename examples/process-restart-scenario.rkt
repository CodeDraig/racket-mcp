#lang mcp
(module+ test
  (require rackunit racket/file racket/runtime-path)
  (define-runtime-path approval "approval.rkt")
  (define directory (make-temporary-file "mcp-restart-example-~a" 'directory))
  (define state (build-path directory "workflow.sqlite")))

(scenario (restart-approval child)
  #:command (list (find-executable-path "racket") approval "--state" state)
  #:capabilities (hasheq 'elicitation (hasheq))
  (define arguments (hasheq 'name "approve" 'arguments (hasheq 'name "Ada")))
  (define pending (hash-ref (scenario-process-call child "tools/call" arguments) 'result))
  (scenario-process-kill! child)
  (scenario-process-restart! child)
  (define completed
    (hash-ref (scenario-process-call child "tools/call"
      (hash-set (hash-set arguments 'requestState (hash-ref pending 'requestState))
                'inputResponses (hasheq 'answer (hasheq 'action "decline")))) 'result))
  (check-equal? (hash-ref (hash-ref completed 'structuredContent) 'greeting) "Hello, Ada"))
(module+ test (delete-directory/files directory))
