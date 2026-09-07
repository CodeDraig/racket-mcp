#lang racket/base
(require rackunit mcp mcp/upstream)
(define snapshot (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities (hasheq 'tools (hasheq)))
  'tools/list (hasheq 'tools (list (hasheq 'name "required" 'inputSchema (hasheq 'type "object"))))
  'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '())
  'prompts/list (hasheq 'prompts '())))
(define requirements (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))))
(for ([durable? '(#f #t)])
  (define calls 0)
  (define (peer method params)
    (cond [(hash-ref snapshot (string->symbol method) #f) => values]
          [else (set! calls (add1 calls))
                (hasheq 'error (hasheq 'code -32021 'message "Tasks required" 'data requirements))]))
  (define store (open-memory-store))
  (define interface (make-upstream-interface snapshot peer #:bridge
    (and durable? (make-upstream-bridge #:identity "capability" #:version "1" #:credential-id (lambda (_) "account")))))
  (define rt (make-runtime interface #:store store))
  (dynamic-wind void
    (lambda ()
      (define (invoke)
        (parameterize ([current-workflow-invocation-key "same-invocation"])
          (dispatch rt "tools/call" (hasheq 'name "required" '_meta (request-meta)))))
      (for ([i (in-range 2)])
        (check-exn (lambda (failure) (and (exn:fail:mcp? failure)
          (equal? (exn:fail:mcp-code failure) -32021) (equal? (exn:fail:mcp-data failure) requirements))) invoke))
      ;; A recorded capability rejection does not silently replay the invocation.
      (check-equal? calls (if durable? 1 2)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
