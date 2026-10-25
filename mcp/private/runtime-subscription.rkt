#lang racket/base
(require racket/list "runtime-state.rkt" "runtime-policy.rkt" "runtime-tasks.rkt" "../clock.rkt" "../descriptor.rkt"
         "../tasks.rkt" "../authorization.rkt" "../subscription.rkt" "../error.rkt")
(provide dispatch-subscription)
(define (dispatch-subscription rt params)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (define id (request-context-request-id context))
  (define notify (request-context-notify context))
  (define meta (hash-ref params '_meta))
  (define requested (checked-subscription-filter params))
  (define accepted
    (for/fold ([accepted (hasheq)]) ([key '(toolsListChanged promptsListChanged resourcesListChanged resourceSubscriptions)]
                                    [available (list (pair? (interface-descriptor-tools iface)) (pair? (interface-descriptor-prompts iface)) (pair? (interface-descriptor-resources iface)) (pair? (interface-descriptor-resources iface)))])
      (if (and available (hash-ref requested key #f)) (hash-set accepted key (hash-ref requested key)) accepted)))
  (for ([key '(toolsListChanged promptsListChanged resourcesListChanged)]
        [method '("tools/list" "prompts/list" "resources/list")])
    (when (and (hash-ref accepted key #f)
               (not ((runtime-authorize rt) principal method (hasheq '_meta meta))))
      (mcp-error -32001 "List-change subscription is not authorized")))
  (when (hash-has-key? accepted 'resourceSubscriptions)
    (define uris (remove-duplicates (hash-ref accepted 'resourceSubscriptions)))
    (for ([uri (in-list uris)])
      (unless ((runtime-authorize rt) principal "resources/read" (hasheq 'uri uri '_meta meta))
        (mcp-error -32001 "Resource subscription is not authorized")))
    (set! accepted (hash-set accepted 'resourceSubscriptions uris)))
  (when (hash-has-key? requested 'taskIds)
    (define ids (hash-ref requested 'taskIds))
    (unless (and (list? ids) (andmap string? ids)) (mcp-error -32602 "taskIds must be an array of strings"))
    (unless (runtime-store rt) (mcp-error -32601 "Tasks are not configured"))
    (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)
      (mcp-error -32021 "Client Tasks capability is required"
        (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
    (for ([task-id (in-list ids)])
      (authorize-upstream-task! rt principal task-id)
      (unless ((runtime-authorize rt) principal "tasks/get" (hasheq 'taskId task-id))
        (mcp-error -32001 "Task subscription is not authorized"))
      (get-task (runtime-store rt) task-id (principal-key principal)))
    (set! accepted (hash-set accepted 'taskIds (remove-duplicates ids))))
  (define (notification-authorized? notice)
    (and (or (not (verified-principal? principal))
             (> (verified-principal-expiry principal) (mcp-current-seconds)))
         (with-handlers ([(lambda (_) #t) (lambda (_) #f)])
           (define method (hash-ref notice 'method #f))
           (define values (hash-ref notice 'params (hasheq)))
           (define target
             (cond [(equal? method "notifications/tools/list_changed") "tools/list"]
                   [(equal? method "notifications/prompts/list_changed") "prompts/list"]
                   [(equal? method "notifications/resources/list_changed") "resources/list"]
                   [(equal? method "notifications/resources/updated") "resources/read"]
                   [(equal? method "notifications/tasks") "tasks/get"]
                   [else #f]))
           (and target
                ((runtime-authorize rt) principal target
                  (cond [(equal? target "resources/read") (hasheq 'uri (hash-ref values 'uri #f) '_meta meta)]
                        [(equal? target "tasks/get") (hasheq 'taskId (hash-ref values 'taskId #f) '_meta meta)]
                        [else (hasheq '_meta meta)]))
                (or (not (equal? target "tasks/get"))
                    (and (runtime-store rt)
                         (begin (authorize-upstream-task! rt principal (hash-ref values 'taskId #f)) #t)))))))
  (listen-subscription (runtime-subscriptions rt) id principal accepted
    (lambda (notice)
      (when (or (equal? (hash-ref notice 'method #f) "notifications/subscriptions/acknowledged")
                (notification-authorized? notice))
        (notify notice))))
)
