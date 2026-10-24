#lang racket/base
(require racket/list
         "build.rkt"
         (submod "build.rkt" private)
         "clock.rkt"
         "descriptor.rkt"
         "json.rkt"
         "workflow.rkt"
         "subscription.rkt"
         "freshness.rkt"
         "authorization.rkt"
         "error.rkt"
         (only-in "tasks.rkt" current-task-notify)
         "private/request-meta.rkt"
         "private/request-message.rkt"
         "private/progress.rkt"
         "private/failure.rkt"
         "private/task-observation.rkt"
         "private/pagination.rkt"
         "private/runtime-state.rkt"
         "private/runtime-policy.rkt"
         "private/runtime-changes.rkt"
         "private/runtime-tasks.rkt"
         "private/runtime-render.rkt"
         "private/runtime-workflow.rkt"
         "private/runtime-resource.rkt"
         "private/runtime-tool.rkt"
         "private/runtime-prompt.rkt"
         "private/runtime-completion.rkt"
         "private/runtime-subscription.rkt"
         "private/runtime-discovery.rkt")
(provide runtime-build-identity runtime-clock runtime-report-change! runtime-drain-changes! runtime-observe-upstream-task! protocol-version recover-runtime-tasks! retry-runtime-task! make-runtime (struct-out runtime) dispatch dispatch-message
         (struct-out exn:fail:mcp) mcp-error request-meta validate-request-meta)
(provide runtime-reconcile-changes!)

(module* upstream-task-subscriptions #f
  (provide runtime-upstream-task-target runtime-upstream-subscription-ended!))
(define (runtime-upstream-task-target rt id snapshot principal capabilities)
  (parameterize ([current-upstream-task-observation (cons id (task-subscription-target snapshot))])
    (dispatch rt "tasks/get" (hasheq 'taskId id '_meta (request-meta #:capabilities capabilities)) #:principal principal)))
(define (runtime-observe-upstream-task! rt id detail #:principal principal #:capabilities capabilities)
  (unless (and (string? id) (hash? detail))
    (raise-arguments-error 'runtime-observe-upstream-task! "expected a local task ID and upstream detail object" "id" id "detail" detail))
  (define frozen (string->json (json->string detail)))
  (parameterize ([current-upstream-task-observation
                  (cons id (hash-set (hash-remove frozen '_meta) 'resultType "complete"))])
    (dispatch rt "tasks/get" (hasheq 'taskId id '_meta (request-meta #:capabilities capabilities)) #:principal principal)))
(define (default-cache-context principal)
  (cond [(verified-principal? principal)
         (json->string (hasheq 'subject (verified-principal-subject principal) 'issuer (verified-principal-issuer principal)
                              'audience (verified-principal-audience principal) 'scopes (verified-principal-scopes principal)
                              'expiry (verified-principal-expiry principal)))]
        [(string? principal) (string->immutable-string principal)]
        [else principal]))
(define (make-runtime interface #:authorize [authorize (lambda (principal method params) #t)] #:store [store #f] #:adapters [adapters (hasheq)]
                      #:clock [clock (current-mcp-clock)] #:build-id [build-id (current-build-identity)] #:recover-tasks? [recover? #t] #:restore-principal [restore-principal values] #:cache [cache (make-resource-cache #:clock clock)] #:cache-context [cache-context default-cache-context]
                      #:page-size [page-size 100] #:cursor-ttl [cursor-ttl 60]
                      #:cursor-limit [cursor-limit 1024] #:cursor-bytes [cursor-bytes 16777216]
                      #:cursor-clock [cursor-clock (lambda () (parameterize ([current-mcp-clock clock]) (mcp-current-seconds)))]
                      #:required-scopes [required-scopes (lambda (method params) '())])
  (set! build-id (normalize-build-identity build-id))
  (unless (and (procedure? clock) (procedure-arity-includes? clock 0))
    (raise-argument-error 'make-runtime "clock procedure accepting zero arguments" clock))
  ;; Public raw descriptors must pass the same interface checks before recovery
  ;; can execute application work. Preserve already-normalized descriptors,
  ;; but retain remapped completion targets when raw construction needs them.
  (define checked-interface (make-interface #:server (interface-descriptor-server interface)
                        #:tools (interface-descriptor-tools interface)
                        #:resources (interface-descriptor-resources interface)
                        #:prompts (interface-descriptor-prompts interface)
                        #:completions (interface-descriptor-completions interface)
                        #:requirements (interface-requirements interface)
                        #:adapter-bindings (interface-adapter-bindings interface)
                        #:adapter-restrictions (interface-adapter-restrictions interface)
                        #:references (interface-resource-references interface)))
  (unless (andmap eq? (interface-descriptor-completions interface)
                     (interface-descriptor-completions checked-interface))
    (set! interface checked-interface))
  (define (operation-scopes method params)
    (append (check-scopes! (required-scopes method params))
            (declaration-scopes interface store method params)))
  (define (scopes method params)
    (remove-duplicates
      (append (operation-scopes method params)
        (if (equal? method "subscriptions/listen")
            (append-map (lambda (target) (operation-scopes (car target) (cdr target)))
                        (subscription-policy-targets interface store params))
            '()))))
  (define (scope-authorize principal method params)
    (define needed (scopes method params))
    (and (or (null? needed) (scopes-allow? principal needed)) (authorize principal method params)))
  (define rt (clocked-runtime interface scope-authorize store (for/hasheq ([(name adapter) (in-hash adapters)]) (values name adapter)) (make-custodian) (make-subscription-hub) cache cache-context (gensym 'runtime-cache)
                              (make-pagination #:page-size page-size #:ttl cursor-ttl #:limit cursor-limit
                                               #:max-bytes cursor-bytes #:clock cursor-clock) scopes clock build-id))
  (with-handlers ([(lambda (_) #t) (lambda (e) (custodian-shutdown-all (runtime-custodian rt)) (raise e))])
    (when (and store recover?) (recover-runtime-tasks! rt #:restore-principal restore-principal)))
  rt)
(define/clock (dispatch rt method params #:principal [principal 'local] #:id [id #f] #:notify [notify void])
  (define meta (validate-request-meta params))
  (call-with-progress-scope (hash-ref meta 'progressToken missing) notify
    (lambda () (dispatch/core rt method params #:principal principal #:id id #:notify notify))))
(define (dispatch/core rt method params #:principal principal #:id id #:notify notify)
  (define meta (validate-request-meta params))
  (define caps (hash-ref meta 'io.modelcontextprotocol/clientCapabilities missing))
  (unless (hash? caps) (mcp-error -32602 "clientCapabilities must be an object"))
  (when (and (verified-principal? principal) (<= (verified-principal-expiry principal) (mcp-current-seconds)))
    (mcp-error -32001 "Principal has expired"))
  (unless ((runtime-authorize rt) principal method params) (mcp-error -32001 "Operation is not authorized"))
  (define iface (runtime-interface rt))
  (when (or (and (member method '("prompts/list" "prompts/get")) (null? (interface-descriptor-prompts iface)))
            (and (member method '("resources/list" "resources/templates/list" "resources/read")) (null? (interface-descriptor-resources iface)))
            (and (member method '("tools/list" "tools/call")) (null? (interface-descriptor-tools iface))))
    (mcp-error -32601 "Capability is not installed"))
  (define context (request-context principal caps id (current-cancelled?) notify))
  (define (render-call compute fingerprint)
    (render-runtime-call rt method params context dispatch compute fingerprint))
  (define (run-domain program arguments)
    (run-domain-workflow rt method principal caps program arguments))
  (parameterize ([current-request-context context]
                 [current-progress-token (hash-ref meta 'progressToken #f)]
                 [current-interface iface]
                 [current-resource-resolver (make-runtime-resource-resolver rt meta context dispatch)]
                 [current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                 [current-task-notify (task-notifier rt)]
                 [current-workflow-store (runtime-store rt)] [current-workflow-adapters (request-adapters rt method params)]
                 [current-workflow-state (hash-ref params 'requestState #f)] [current-workflow-responses (hash-ref params 'inputResponses (hasheq))])
    (case (string->symbol method)
      [(server/discover tools/list resources/list resources/templates/list prompts/list)
       (dispatch-discovery rt method params)]
      [(tools/call) (dispatch-tool-call rt params render-call)]
      [(completion/complete) (dispatch-completion iface params)]
      [(subscriptions/listen) (dispatch-subscription rt params)]
      [(tasks/get tasks/update tasks/cancel) (dispatch-runtime-task rt method params)]
      [(resources/read) (dispatch-resource-read rt params render-call run-domain)]
      [(prompts/get) (dispatch-prompt-get rt params render-call run-domain)]
      [else (mcp-error -32601 "Method not found")])))
(define (dispatch-message rt message #:principal [principal 'local] #:notify [notify void])
  (define id (if (hash? message) (hash-ref message 'id missing) missing))
  (define (error-response e)
    (define detail (hasheq 'code (if (exn:fail:mcp? e) (exn:fail:mcp-code e) -32603)
                          'message (if (exn:fail:mcp? e) (exn-message e) "Internal error")))
    (define body (hasheq 'jsonrpc "2.0" 'error (if (and (exn:fail:mcp? e) (exn:fail:mcp-data e)) (hash-set detail 'data (exn:fail:mcp-data e)) detail)))
    (if (or (missing? id) (not (request-id? id))) body (hash-set body 'id id)))
  (with-handlers ([non-break-failure? error-response])
    (check-client-message message)
    (if (missing? id) #f
        (hasheq 'jsonrpc "2.0" 'id id 'result (dispatch rt (hash-ref message 'method) (hash-ref message 'params (hasheq)) #:principal principal #:id id #:notify notify)))))
