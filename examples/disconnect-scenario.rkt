#lang mcp
(require mcp/subscription)
(module+ test (require rackunit mcp/stdio))

(tool (wait-for-disconnect)
  (progress! (current-progress-token) 1 #:message "Handler started")
  (sync never-evt))
(tool (hello) (text-result "Connected again"))

(scenario (transport-loss session)
  #:interface mcp-interface
  #:transport 'stdio
  (define pending
    (scenario-request session "tools/call"
      (hasheq 'name "wait-for-disconnect" '_meta (hasheq 'progressToken "started"))))
  (define started (sync/timeout 2 (request-handle-notifications pending)))
  (check-equal? (hash-ref started 'method) "notifications/progress")
  (scenario-disconnect! session)
  (define lost (sync/timeout 2 pending))
  (check-true (exn? lost))
  (check-false (exn:fail:request-cancelled? lost))
  (scenario-reconnect! session)
  (check-equal?
    (hash-ref (hash-ref (scenario-call session "tools/call" (hasheq 'name "hello")) 'result) 'content)
    (list (text-content "Connected again"))))
