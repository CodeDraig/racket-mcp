#lang racket/base
(require rackunit racket/list mcp mcp/scenario)

(define form (hasheq 'mode "form" 'message "Choose a value"
                    'requestedSchema (object-schema (hasheq 'value String))))
(workflow (choose) #:version "1"
  (await-input ([first Any form] [second Any form]))
  (structured-result (hasheq 'first first 'second second)))

(for ([transport '(local stdio http)])
  (test-case (format "~a authored conflicting input submissions" transport)
    (call-with-scenario-session (make-interface #:tools (list choose))
      (lambda (session)
        (define start (scenario-call session "tools/call" (hasheq 'name "choose")))
        (define state (hash-ref (hash-ref start 'result) 'requestState))
        (define (answer name) (hasheq 'action "accept" 'content (hasheq 'value name)))
        (define (params responses)
          (hasheq 'name "choose" 'requestState state 'inputResponses responses))
        ;; Both requests are live before either result is observed. The test
        ;; permits either winner; exactly one original response must be kept.
        (define requests
          (for/list ([value '("Ada" "Grace")])
            (scenario-request session "tools/call" (params (hasheq 'first (answer value))))))
        (define replies (map (lambda (h) (sync/timeout 5 h)) requests))
        (check-true (andmap hash? replies))
        (check-not-equal? (hash-ref (car replies) 'id) (hash-ref (cadr replies) 'id))
        (check-equal? (count (lambda (r) (hash-has-key? r 'result)) replies) 1)
        (check-equal? (count (lambda (r) (hash-has-key? r 'error)) replies) 1)
        (define winner (if (hash-has-key? (car replies) 'result) "Ada" "Grace"))
        (define accepted (hash-ref (findf (lambda (r) (hash-has-key? r 'result)) replies) 'result))
        (check-equal? (hash-keys (hash-ref accepted 'inputRequests)) '(second))
        (define repeated (scenario-call session "tools/call" (params (hasheq 'first (answer winner)))))
        (check-equal? (hash-ref repeated 'result) accepted)
        (define declined (hasheq 'action "decline"))
        (define complete (scenario-call session "tools/call" (params (hasheq 'second declined))))
        (check-equal? (hash-ref (hash-ref complete 'result) 'structuredContent)
                      (hasheq 'first (answer winner) 'second declined)))
      #:transport transport #:capabilities (hasheq 'elicitation (hasheq)))))
