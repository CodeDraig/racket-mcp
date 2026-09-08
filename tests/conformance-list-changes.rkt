#lang racket/base
(require rackunit racket/async-channel mcp mcp/http mcp/stdio
         "../dev/conformance-list-changes.rkt")

(test-case "diagnostic mutations change actual lists before accepted events"
  (define confirmation (make-async-channel))
  (define stop
    (serve-changing-conformance
      (make-interface
        #:tools (list (make-tool "existing" '() (lambda (_) (text-result "unchanged"))))
        #:prompts (list (make-prompt "existing" '() (lambda (_) '()))))
      #:confirmation confirmation))
  (dynamic-wind void
    (lambda ()
      (define port (sync/timeout 5 confirmation))
      (check-true (exact-positive-integer? port))
      (define client (make-http-client (format "http://127.0.0.1:~a/mcp" port)))
      (for ([kind '(tools prompts)] [hook '("test_trigger_tool_change" "test_trigger_prompt_change")]
            [filter '(toolsListChanged promptsListChanged)]
            [added '("diagnostic_added_tool" "diagnostic_added_prompt")])
        (define method (format "~a/list" kind))
        (define (names)
          (map (lambda (d) (hash-ref d 'name)) (hash-ref (hash-ref (http-client-call client method) 'result) kind)))
        (define before (names))
        (check-false (member added before))
        (define handle (http-client-request client "subscriptions/listen"
                        (hasheq 'notifications (hasheq filter #t))))
        (define ack (sync/timeout 5 (request-handle-notifications handle)))
        (check-equal? (hash-ref ack 'method) "notifications/subscriptions/acknowledged")
        (for ([present? '(#t #f)])
          (http-client-call client "tools/call" (hasheq 'name hook 'arguments (hasheq)))
          (define event (sync/timeout 5 (request-handle-notifications handle)))
          (check-equal? (hash-ref event 'method) (format "notifications/~a/list_changed" kind))
          (define after (names))
          (check-equal? (and (member added after) #t) present?)
          (check-equal? (sort (remove added after) string<?) (sort before string<?)))
        (request-cancel! handle)
        (check-true (exn:fail:request-cancelled? (sync/timeout 5 handle)))))
    stop))
