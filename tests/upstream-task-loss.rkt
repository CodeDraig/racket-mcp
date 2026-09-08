#lang racket/base
(require rackunit racket/async-channel mcp mcp/upstream mcp/upstream-subscription mcp/scenario mcp/stdio)
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28")
           'capabilities (hasheq 'tools (hasheq) 'extensions (hash-ref caps 'extensions)))
    'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object"))))
    'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '())
    'prompts/list (hasheq 'prompts '())))
(for* ([transport '(local stdio http)] [mode '(loss complete cancel empty)])
  (test-case (format "task feed termination: ~a/~a" transport mode)
    (define creations 0)
    (define (peer method params)
      (cond [(hash-ref snapshot (string->symbol method) #f) => values]
            [(equal? method "tools/call")
             (set! creations (add1 creations))
             (hasheq 'resultType "task" 'taskId (format "remote-~a" creations) 'status "working"
               'createdAt "2026-09-08T00:00:00Z" 'lastUpdatedAt "2026-09-08T00:00:00Z" 'ttlMs 60000)]
            [else (error 'peer "feed termination must not poll or mutate a task")]))
    (define source (make-upstream-interface snapshot peer #:bridge
      (make-upstream-bridge #:identity "task-loss" #:version "1" #:credential-id (lambda (_) "credential"))))
    (call-with-scenario-session source
      (lambda (session)
        (define rt (scenario-session-runtime session))
        (define ids (for/list ([i (in-range 2)])
          (hash-ref (hash-ref (scenario-call session "tools/call" (hasheq 'name "work")) 'result) 'taskId)))
        (define before (map (lambda (id) (load-instance (runtime-store rt) id)) ids))
        (define (listen id)
          (define handle (scenario-request session "subscriptions/listen" (hasheq 'notifications (hasheq 'taskIds (list id)))))
          (check-equal? (hash-ref (sync/timeout 2 (request-handle-notifications handle)) 'method)
                        "notifications/subscriptions/acknowledged")
          handle)
        (define affected (listen (car ids)))
        (define unrelated (listen (cadr ids)))
        (define ready (make-semaphore))
        (define result (box #f))
        (define notices (make-async-channel))
        (define (finish value) (set-box! result value) (semaphore-post ready))
        (define handle (request-handle 77 ready result
          (lambda () (unless (sync/timeout 0 (semaphore-peek-evt ready))
            (finish (exn:fail:request-cancelled "local stop" (current-continuation-marks) 77)))) notices))
        (define (request method params)
          (if (equal? method "subscriptions/listen") handle
              (request-handle 1 (make-semaphore 1) (box (hasheq 'result (hash-ref snapshot (string->symbol method))))
                void (make-async-channel))))
        (async-channel-put notices (hasheq 'method "notifications/subscriptions/acknowledged"
          'params (hasheq 'notifications (hasheq 'taskIds (if (eq? mode 'empty) '() '("remote-1")))
            '_meta (hasheq 'io.modelcontextprotocol/subscriptionId 77))))
        (check-not-false
          (call-with-upstream-task-subscription rt snapshot request ids
            (lambda (subscription)
              (check-equal? (upstream-task-subscription-accepted subscription) (if (eq? mode 'empty) '() (list (car ids))))
              (case mode
                [(loss empty) (finish (exn:fail "upstream connection lost" (current-continuation-marks)))]
                [(complete) (finish (hasheq 'result (hasheq 'resultType "complete"
                  '_meta (hasheq 'io.modelcontextprotocol/subscriptionId 77))))]
                [(cancel) (stop-upstream-task-subscription! subscription)])
              (sync/timeout 2 subscription)) #:principal "alice" #:capabilities caps))
        (define ended (sync/timeout (if (eq? mode 'empty) 0 2) affected))
        (if (eq? mode 'empty) (check-false ended)
         (begin
          (check-true (hash? ended))
          (if (eq? mode 'loss)
            (begin (check-equal? (hash-ref (hash-ref ended 'error) 'code) -32000)
                   (check-regexp-match #rx"re-listen and refresh" (hash-ref (hash-ref ended 'error) 'message)))
            (check-equal? (hash-ref (hash-ref ended 'result) 'resultType) "complete"))))
        (check-false (sync/timeout 0 unrelated))
        (check-false (sync/timeout 0 (request-handle-notifications affected)))
        (check-false (sync/timeout 0 (request-handle-notifications unrelated)))
        (for ([id ids] [old before])
          (define current (load-instance (runtime-store rt) id))
          (check-equal? (stored-instance-revision current) (stored-instance-revision old))
          (check-equal? (stored-instance-state current) (stored-instance-state old)))
        (check-equal? creations 2)
        (when (eq? mode 'empty) (request-cancel! affected))
        (request-cancel! unrelated)) #:transport transport #:principal "alice" #:capabilities caps)))
