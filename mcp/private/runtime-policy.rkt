#lang racket/base
(require racket/list "runtime-state.rkt" "adapter-policy.rkt" "handler-info.rkt"
         "../descriptor.rkt" "../storage.rkt" "../workflow.rkt" "../error.rkt")
(provide resolve-task-operation checked-subscription-filter subscription-policy-targets
         operation-targets declaration-scopes operation-adapters request-adapters lookup-operation)
(define (task-operation? d instance)
  (or (and (task-handler? (tool-descriptor-handler d))
           ((task-handler-matches? (tool-descriptor-handler d)) instance))
  (and (tool-descriptor-workflow d)
       (equal? (stored-instance-operation instance)
               (string-append "task:" (workflow-descriptor-name (tool-descriptor-workflow d))))
       (let ([name (hash-ref (stored-instance-state instance) 'operationName #f)])
         (or (not name) (equal? name (tool-descriptor-name d)))))))
(define (resolve-task-operation tools instance)
  (define matches (filter (lambda (d) (task-operation? d instance)) tools))
  (when (> (length matches) 1)
    (mcp-error -32001 "Task operation is ambiguous; explicit recovery is required"))
  (and (pair? matches) (car matches)))
;; Shared by scope preflight and runtime registration; no readers or workers run.
(define (checked-subscription-filter params)
  (define requested (hash-ref params 'notifications #f))
  (unless (hash? requested) (mcp-error -32602 "notifications filter must be an object"))
  (for ([key '(toolsListChanged promptsListChanged resourcesListChanged)])
    (when (and (hash-has-key? requested key) (not (boolean? (hash-ref requested key))))
      (mcp-error -32602 "List-change subscription filters must be booleans")))
  (for ([key '(resourceSubscriptions taskIds)])
    (when (hash-has-key? requested key)
      (define values (hash-ref requested key))
      (unless (and (list? values) (andmap string? values))
        (mcp-error -32602 (format "~a must be an array of strings" key)))))
  requested)
(define (subscription-policy-targets interface store params)
  (define requested (checked-subscription-filter params))
  (define meta (hash-ref params '_meta (hasheq)))
  (append
    (for/list ([key '(toolsListChanged promptsListChanged resourcesListChanged)]
               [method '("tools/list" "prompts/list" "resources/list")]
               [declarations (list (interface-descriptor-tools interface)
                                   (interface-descriptor-prompts interface)
                                   (interface-descriptor-resources interface))]
               #:when (and (pair? declarations) (hash-ref requested key #f)))
      (cons method (hasheq '_meta meta)))
    (if (pair? (interface-descriptor-resources interface))
        (for/list ([uri (in-list (remove-duplicates (hash-ref requested 'resourceSubscriptions '())))])
          (cons "resources/read" (hasheq 'uri uri '_meta meta)))
        '())
    (if store
        (for/list ([id (in-list (remove-duplicates (hash-ref requested 'taskIds '())))])
          (cons "tasks/get" (hasheq 'taskId id '_meta meta)))
        '())))
(define (operation-targets interface store method params)
  (define tools (interface-descriptor-tools interface))
  (define resources (interface-descriptor-resources interface))
  (define prompts (interface-descriptor-prompts interface))
  (define targets
    (case (string->symbol method)
      [(tools/call) (filter (lambda (d) (equal? (tool-descriptor-name d) (hash-ref params 'name #f))) tools)]
      [(prompts/get) (filter (lambda (d) (equal? (prompt-descriptor-name d) (hash-ref params 'name #f))) prompts)]
      [(resources/read)
       (define uri (hash-ref params 'uri #f))
       (if (string? uri) (filter (lambda (d) ((resource-descriptor-matcher d) uri)) resources) '())]
      [(completion/complete)
       (define ref (hash-ref params 'ref (hasheq)))
       (if (not (hash? ref)) '()
           (case (hash-ref ref 'type #f)
             [("ref/prompt") (filter (lambda (d) (equal? (prompt-descriptor-name d) (hash-ref ref 'name #f))) prompts)]
             [("ref/resource") (filter (lambda (d) (equal? (resource-descriptor-uri d) (hash-ref ref 'uri #f))) resources)]
             [else '()]))]
      [(tasks/get tasks/update tasks/cancel)
       (define id (hash-ref params 'taskId #f))
       (define instance (and store (string? id) (load-instance store id)))
       (cond [(not instance) '()]
             [else
              (define tool (resolve-task-operation tools instance))
              (unless tool (mcp-error -32001 "Task operation is absent from this interface"))
              (list tool)])]
      [else '()]))
  targets)
(define (declaration-scopes interface store method params)
  (remove-duplicates (append-map (lambda (target) (hash-ref (interface-requirements interface) target '()))
    (operation-targets interface store method params))))
(define (operation-adapters rt target)
  (define bindings
    (for/fold ([bindings (runtime-adapters rt)])
            ([(name adapter) (in-hash (hash-ref (interface-adapter-bindings (runtime-interface rt)) target (hasheq)))])
      (hash-set bindings name adapter)))
  (restrict-adapters bindings
    (hash-ref (interface-adapter-restrictions (runtime-interface rt)) target #f)
    #:parent (current-workflow-adapters)))
(define (request-adapters rt method params)
  (define targets (operation-targets (runtime-interface rt) (runtime-store rt) method params))
  (if (= (length targets) 1) (operation-adapters rt (car targets))
      (restrict-adapters (runtime-adapters rt) #f #:parent (current-workflow-adapters))))
(define (lookup-operation declarations name-of params key)
  (or (findf (lambda (d) (equal? (name-of d) (hash-ref params key #f))) declarations)
      (mcp-error -32602 (format "Unknown ~a" key))))
