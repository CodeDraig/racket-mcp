#lang racket/base
(require "private/handler-info.rkt" "private/task-observation.rkt")
(require "private/adapter-policy.rkt" "external-changes.rkt" (submod "workflow.rkt" private))
(provide runtime-reconcile-changes!)
(require "clock.rkt" "private/failure.rkt" "private/embedded-content.rkt" "private/request-message.rkt" "private/progress.rkt" racket/list racket/match net/base64 "descriptor.rkt" "schema.rkt" "json.rkt" "workflow.rkt" "tasks.rkt" "storage.rkt" "subscription.rkt" "error.rkt" "completion.rkt" "authorization.rkt" "rendering.rkt" "presentation.rkt" "freshness.rkt" "private/pagination.rkt")
(provide runtime-clock runtime-report-change! runtime-drain-changes! runtime-observe-upstream-task! protocol-version recover-runtime-tasks! retry-runtime-task! make-runtime (struct-out runtime) dispatch dispatch-message
         (struct-out exn:fail:mcp) mcp-error request-meta validate-request-meta)
(define protocol-version "2026-07-28")
(struct resource-snapshot (result reads keys expires) #:transparent)
(define current-resource-snapshots (make-parameter #f))
(define (snapshot-with-ttl snapshot ttl)
  (struct-copy resource-snapshot snapshot [result (hash-set (resource-snapshot-result snapshot) 'ttlMs ttl)]))
(define current-embedding-stack (make-parameter '()))
(struct runtime (interface authorize store adapters custodian subscriptions cache cache-context cache-namespace pagination required-scopes) #:transparent)
(struct clocked-runtime runtime (clock))
(define (runtime-clock rt)
  (if (clocked-runtime? rt) (clocked-runtime-clock rt) (current-mcp-clock)))
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
(define-syntax-rule (define/clock (name rt . arguments) body ...)
  (define (name rt . arguments)
    (parameterize ([current-mcp-clock (runtime-clock rt)]) body ...)))
(define (default-cache-context principal)
  (cond [(verified-principal? principal)
         (json->string (hasheq 'subject (verified-principal-subject principal) 'issuer (verified-principal-issuer principal)
                              'audience (verified-principal-audience principal) 'scopes (verified-principal-scopes principal)
                              'expiry (verified-principal-expiry principal)))]
        [(string? principal) (string->immutable-string principal)]
        [else principal]))
(define (make-runtime interface #:authorize [authorize (lambda (principal method params) #t)] #:store [store #f] #:adapters [adapters (hasheq)]
                      #:clock [clock (current-mcp-clock)] #:recover-tasks? [recover? #t] #:restore-principal [restore-principal values] #:cache [cache (make-resource-cache #:clock clock)] #:cache-context [cache-context default-cache-context]
                      #:page-size [page-size 100] #:cursor-ttl [cursor-ttl 60]
                      #:cursor-limit [cursor-limit 1024] #:cursor-bytes [cursor-bytes 16777216]
                      #:cursor-clock [cursor-clock (lambda () (parameterize ([current-mcp-clock clock]) (mcp-current-seconds)))]
                      #:required-scopes [required-scopes (lambda (method params) '())])
  (unless (and (procedure? clock) (procedure-arity-includes? clock 0))
    (raise-argument-error 'make-runtime "clock procedure accepting zero arguments" clock))
  ;; Public raw descriptors must pass the same interface checks before recovery
  ;; can execute application work. Preserve the supplied descriptor's identity.
  (void (make-interface #:server (interface-descriptor-server interface)
                        #:tools (interface-descriptor-tools interface)
                        #:resources (interface-descriptor-resources interface)
                        #:prompts (interface-descriptor-prompts interface)
                        #:completions (interface-descriptor-completions interface)
                        #:requirements (interface-requirements interface)
                        #:adapter-bindings (interface-adapter-bindings interface)
                        #:adapter-restrictions (interface-adapter-restrictions interface)
                        #:references (interface-resource-references interface)))
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
                                               #:max-bytes cursor-bytes #:clock cursor-clock) scopes clock))
  (with-handlers ([(lambda (_) #t) (lambda (e) (custodian-shutdown-all (runtime-custodian rt)) (raise e))])
    (when (and store recover?) (recover-runtime-tasks! rt #:restore-principal restore-principal)))
  rt)
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
(define (change-keys! keys)
  (unless (and (list? keys) (json-value? keys)) (error 'freshness "dependency keys must be a JSON list"))
  keys)
(define (resource-notification-authorized? rt principal uri)
  (and (or (not (verified-principal? principal)) (> (verified-principal-expiry principal) (mcp-current-seconds)))
       ((runtime-authorize rt) principal "resources/read" (hasheq 'uri uri '_meta (request-meta)))))
(define (affected-resource-uris rt owner keys cached authorized?)
    (for/list ([target (in-list (subscription-resource-targets (runtime-subscriptions rt)))]
               #:when (equal? owner (principal-key (car target)))
               #:do [(define uri (cdr target))
                     (define reader (car target))
                     (define params (hasheq 'uri uri '_meta (request-meta))) ]
               #:when (authorized? reader uri)
               #:when
               (or (member uri cached)
                   (for/or ([d (in-list (interface-descriptor-resources (runtime-interface rt)))])
                     (define args ((resource-descriptor-matcher d) uri))
                     (and args
                          (parameterize ([current-interface (runtime-interface rt)]
                                         [current-request-context (request-context reader (hasheq) #f (lambda () #f) void)])
                            (define dependencies
                              (change-keys! ((resource-descriptor-depends-on d) (bind-arguments (resource-descriptor-arguments d) args))))
                            (ormap (lambda (key) (member key keys)) dependencies))))))
      uri))
(define/clock (runtime-report-change! rt principal keys)
  (change-keys! keys)
  (define owner (principal-key principal))
  ;; Invalidation precedes publication, including changes arriving externally.
  (define cached (invalidate-keys! (runtime-cache rt) keys #:principal owner))
  (define affected (affected-resource-uris rt owner keys cached
                     (lambda (reader uri) (resource-notification-authorized? rt reader uri))))
  (for ([uri (in-list (remove-duplicates affected))])
    (publish-change! (runtime-subscriptions rt) "notifications/resources/updated" (hasheq 'uri uri)
                     #:principal principal #:principal-key principal-key
                     #:authorized? (lambda (reader) (resource-notification-authorized? rt reader uri))))
  (remove-duplicates (append cached affected)))
(define/clock (runtime-upstream-subscription-ended! rt principal keys ids failed? fallback?)
  (change-keys! keys)
  (define owner (principal-key principal))
  ;; A missing feed makes cached reads uncertain; it is not a committed mutation
  ;; and must not fabricate resources/updated or task-state notifications.
  (define cached (if (null? keys) '() (invalidate-keys! (runtime-cache rt) keys #:principal owner)))
  (define affected
    (if (null? keys) '()
        (if fallback? #f
        (with-handlers ([(lambda (_) #t) (lambda (_) #f)])
          (affected-resource-uris rt owner keys cached (lambda (_reader _uri) #t))))))
  (close-subscriptions! (runtime-subscriptions rt)
    #:matches? (lambda (reader filter)
      (and (equal? owner (principal-key reader))
           (or (ormap (lambda (id) (member id ids)) (hash-ref filter 'taskIds '()))
               (if affected
                   (ormap (lambda (uri) (member uri affected)) (hash-ref filter 'resourceSubscriptions '()))
                   ;; Failed dependency calculation cannot justify retaining a
                   ;; resource listener for this principal with unknown coverage.
                   (pair? (hash-ref filter 'resourceSubscriptions '()))))))
    #:error-message (and failed? "Upstream subscription lost; re-listen and refresh cached data")))
(define/clock (runtime-drain-changes! rt)
  (unless (runtime-store rt) (error 'freshness "outbox storage is not configured"))
  (drain-change-outbox! (runtime-store rt)
                       (lambda (_id principal keys) (runtime-report-change! rt principal keys))))
(define/clock (runtime-reconcile-changes! rt source #:max-events [event-limit 1000] #:max-bytes [byte-limit 1048576])
  (unless (runtime-store rt) (error 'runtime-reconcile-changes! "a configured state store is required"))
  (define result (reconcile-external-changes! (runtime-store rt) source #:max-events event-limit #:max-bytes byte-limit))
  (runtime-drain-changes! rt)
  result)
;; Resolve persisted identity through application policy; credentials are never
;; serialized. Each worker reauthorizes after acquiring its instance lock.
(define/clock (recover-runtime-tasks! rt #:restore-principal [restore-principal values])
  (define store (runtime-store rt))
  (if (not store) '()
      (for/list ([instance (in-list (list-instances store))]
                 #:when (and (not (equal? (hash-ref (stored-instance-state instance) 'kind #f) "upstream-task"))
                             (> (stored-instance-expires instance) (mcp-current-seconds))
                             (equal? (hash-ref (hash-ref (stored-instance-state instance) 'task (hasheq)) 'status #f) "working")))
        (define tool
          (resolve-task-operation (interface-descriptor-tools (runtime-interface rt)) instance))
        (unless tool (error 'recover-runtime-tasks! "no executable for persisted task ~a" (stored-instance-operation instance)))
        (define identity (stored-instance-principal instance))
        (parameterize ([current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                       [current-task-notify (task-notifier rt)])
        (resume-task! (tool-descriptor-workflow tool) store (stored-instance-handle instance) identity
                      #:adapters (operation-adapters rt tool) #:custodian (runtime-custodian rt) #:wait? #f
                      #:authorize
                      (lambda ()
                        (define principal (restore-principal identity))
                        (unless (and principal (equal? (principal-key principal) identity)
                                     (or (not (verified-principal? principal))
                                         (> (verified-principal-expiry principal) (mcp-current-seconds)))
                                     ((runtime-authorize rt) principal "tools/call"
                                      (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance))))
                          (error 'recover-runtime-tasks! "task principal is no longer authorized"))
                        (current-request-context
                         (request-context principal (hash-ref (stored-instance-state instance) 'capabilities (hasheq))
                                          #f (current-cancelled?) void))))))))
(define (task-notifier rt)
  (lambda (principal task)
    (publish-change! (runtime-subscriptions rt) "notifications/tasks" task
                     #:principal principal #:principal-key principal-key
                     #:authorized? (lambda (reader)
                       (and (or (not (verified-principal? reader)) (> (verified-principal-expiry reader) (mcp-current-seconds)))
                            ((runtime-authorize rt) reader "tasks/get" (hasheq 'taskId (hash-ref task 'taskId))))))))
(define (request-meta #:capabilities [caps (hasheq)] #:extra [extra (hasheq)])
  (hash-set* extra 'io.modelcontextprotocol/protocolVersion protocol-version
             'io.modelcontextprotocol/clientCapabilities caps
             'io.modelcontextprotocol/clientInfo (hasheq 'name "racket-mcp" 'version "0.1")))
(define (validate-request-meta params #:version? [version? #t])
  (unless (hash? params) (mcp-error -32602 "params must be an object"))
  (define meta (hash-ref params '_meta #f))
  (unless (and (hash? meta) (string? (hash-ref meta 'io.modelcontextprotocol/protocolVersion #f))
               (hash? (hash-ref meta 'io.modelcontextprotocol/clientCapabilities #f)))
    (mcp-error -32602 "_meta requires protocolVersion and clientCapabilities"))
  (when (and (hash-has-key? meta 'progressToken) (not (progress-token? (hash-ref meta 'progressToken))))
    (mcp-error -32602 "progressToken must be a string or integer"))
  (define version (hash-ref meta 'io.modelcontextprotocol/protocolVersion))
  (unless (or (not version?) (equal? version protocol-version))
    (mcp-error -32022 "Unsupported protocol version" (hasheq 'supported (list protocol-version) 'requested version))) meta)
(define (cache result) (hash-set* result 'ttlMs 0 'cacheScope "private"))
(define (complete key xs) (cache (hasheq 'resultType "complete" key xs)))
(define (tool-wire d)
  (define base (hasheq 'name (tool-descriptor-name d) 'description (tool-descriptor-description d)
                       'inputSchema (tool-descriptor-input-schema d) 'annotations (tool-descriptor-annotations d)))
  (if (tool-descriptor-output-schema d) (hash-set base 'outputSchema (tool-descriptor-output-schema d)) base))
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
  (define (listing key items)
    (paginate (runtime-pagination rt) key items
              (list method (principal-key principal) ((runtime-cache-context rt) principal)
                    (json->string caps) (json->string (hash-remove (hash-remove params '_meta) 'cursor)))
              (hash-ref params 'cursor missing)))
  (define (input-required? result)
    (and (hash? result) (equal? (hash-ref result 'resultType #f) "input_required")
         (string? (hash-ref result 'requestState #f)) (hash? (hash-ref result 'inputRequests #f))))
  (define (run-domain-workflow program arguments)
    (unless (runtime-store rt) (mcp-error -32603 "Workflow storage is not configured"))
    (when (and (ormap (lambda (s) (memq (workflow-stage-kind s) '(input input-group))) (workflow-descriptor-stages program))
               (not (hash-has-key? caps 'elicitation)))
      (mcp-error -32021 "Client elicitation capability is required" (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
    (run-workflow (struct-copy workflow-descriptor program [name (string-append method ":" (workflow-descriptor-name program))])
                  (runtime-store rt) (for/hasheq ([(key value) (in-hash arguments)] #:unless (missing? value)) (values key value))
                  #:principal (principal-key principal) #:state (current-workflow-state)
                  #:responses (current-workflow-responses) #:adapters (current-workflow-adapters)
                  #:cancelled? (current-cancelled?)))
  (define (render-call compute fingerprint)
    (define store (runtime-store rt))
    (define existing-render
      (and store (not (current-workflow-state)) (current-workflow-invocation-key)
           (find-instance-by-key store (principal-key principal) (string-append "render:" method) (current-workflow-invocation-key))))
    (define token (or (current-workflow-state) (and existing-render (stored-instance-handle existing-render))))
    (define resumed? (render-continuation? store token))
    (define saved-workflow
      (and store token (not resumed?)
           (let ([round (resolve-continuation store token)]) (load-instance store (if round (car round) token)))))
    (define render-key
      (or (current-workflow-invocation-key)
          (and saved-workflow (string-append "workflow-render:" (stored-instance-handle saved-workflow)))))
    (define next (if saved-workflow (next-embedding-index (stored-instance-state saved-workflow)) 0))
    (define layout (if resumed? #f (parameterize ([current-render-capture (and store (box next))]) (compute))))
    (if (or resumed? (and store (layout-embeddings? layout)))
        (render-layout store layout #:operation method
                       #:arguments (hash-remove (hash-remove (hash-remove params '_meta) 'requestState) 'inputResponses)
                       #:principal (principal-key principal) #:fingerprint fingerprint
                       #:state (and resumed? token) #:responses (current-workflow-responses)
                       #:key render-key
                       #:authorize (lambda (uri)
                                     (unless ((runtime-authorize rt) principal "resources/read" (hasheq 'uri uri '_meta meta))
                                       (mcp-error -32001 "Embedded resource is not authorized")))
                       #:resolve
                       (lambda (uri child-state child-responses key)
                         (when (or (member uri (current-embedding-stack)) (>= (length (current-embedding-stack)) 32))
                           (mcp-error -32603 "Resource embedding cycle or depth limit"))
                         (parameterize ([current-embedding-stack (cons uri (current-embedding-stack))]
                                        [current-workflow-invocation-key key])
                           (dispatch rt "resources/read"
                                     (if child-state (hasheq '_meta meta 'uri uri 'requestState child-state 'inputResponses child-responses)
                                         (hasheq '_meta meta 'uri uri))
                                     #:principal principal #:id id #:notify notify))))
        layout))
  (define (lookup xs get key)
    (or (findf (lambda (d) (equal? (get d) (hash-ref params key #f))) xs)
        (mcp-error -32602 (format "Unknown ~a" key))))
  (parameterize ([current-request-context (request-context principal caps id (current-cancelled?) notify)]
                 [current-progress-token (hash-ref meta 'progressToken #f)]
                 [current-interface iface]
                 [current-resource-resolver
                  (lambda (ref)
                    (define uri (resource-uri ref))
                    (when (member uri (current-embedding-stack)) (mcp-error -32603 "Resource embedding cycle"))
                    (when (>= (length (current-embedding-stack)) 32) (mcp-error -32603 "Resource embedding depth exceeded"))
                    (parameterize ([current-embedding-stack (cons uri (current-embedding-stack))])
                      (define result (dispatch rt "resources/read" (hasheq '_meta meta 'uri uri) #:principal principal #:id id #:notify notify))
                      (embedded-resource-content result)))]
                 [current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                       [current-task-notify (task-notifier rt)]
                 [current-workflow-store (runtime-store rt)] [current-workflow-adapters (request-adapters rt method params)]
                 [current-workflow-state (hash-ref params 'requestState #f)] [current-workflow-responses (hash-ref params 'inputResponses (hasheq))])
    (case (string->symbol method)
      [(server/discover)
       (define server (interface-descriptor-server iface))
       (define base-capabilities
         (for/fold ([c (hasheq)]) ([k '(tools resources prompts)] [xs (list (interface-descriptor-tools iface) (interface-descriptor-resources iface) (interface-descriptor-prompts iface))])
           (if (null? xs) c
               (hash-set c k (if (eq? k 'resources)
                                 (hasheq 'listChanged #t 'subscribe #t)
                                 (hasheq 'listChanged #t))))))
       (define capabilities
         (let* ([c (if (pair? (interface-descriptor-completions iface)) (hash-set base-capabilities 'completions (hasheq)) base-capabilities)]
                [c (if (and (runtime-store rt) (ormap (lambda (tool) (or (tool-descriptor-workflow tool)
                                                                                       (task-handler? (tool-descriptor-handler tool))))
                                                     (interface-descriptor-tools iface)))
                       (hash-set c 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))) c)]) c))
       (cache (hasheq 'resultType "complete" 'supportedVersions (list protocol-version) 'capabilities capabilities
                      'instructions (if server (server-descriptor-instructions server) "")
                      '_meta (hasheq 'io.modelcontextprotocol/serverInfo
                                    (hasheq 'name (if server (server-descriptor-name server) "mcp") 'version (if server (server-descriptor-version server) "0")))))]
      [(tools/list) (listing 'tools (map tool-wire (interface-descriptor-tools iface)))]
      [(tools/call)
       (define d (lookup (interface-descriptor-tools iface) tool-descriptor-name 'name))
       (define args (hash-ref params 'arguments (hasheq)))
       (unless (valid? (tool-descriptor-input-schema d) args) (mcp-error -32602 "Invalid tool arguments"))
       (define bound (if (tool-descriptor-raw? d) args (bind-arguments (tool-descriptor-arguments d) args)))
       (define task? (or (eq? (tool-descriptor-execution d) 'task)
                         (and (eq? (tool-descriptor-execution d) 'task-optional)
                              (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks))))
       (when (and task? (not (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)))
         (mcp-error -32021 "Client Tasks capability is required" (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
       (when (and (tool-descriptor-workflow d)
                  (ormap (lambda (s) (memq (workflow-stage-kind s) '(input input-group))) (workflow-descriptor-stages (tool-descriptor-workflow d)))
                  (not (hash-has-key? caps 'elicitation))) (mcp-error -32021 "Client elicitation capability is required" (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
       (define (invoke-handler)
         (define outcome ((tool-descriptor-handler d) bound))
         (cond [(committed-result? outcome)
                (define value (committed-result-result outcome))
                (unless (and (hash? value) (equal? (hash-ref value 'resultType #f) "complete")
                             (not (hash-ref value 'isError #f)))
                  (mcp-error -32603 "A commit acknowledgement requires a successful complete result"))
                (define keys (change-keys! (append (change-keys! (committed-result-keys outcome))
                                                 (change-keys! ((tool-descriptor-changes d) bound value)))))
                (unless (null? keys)
                  (if (runtime-store rt)
                      (begin (record-committed-change! (runtime-store rt) (principal-key principal) keys)
                             (runtime-drain-changes! rt))
                      (runtime-report-change! rt principal keys)))
                value]
               [else outcome]))
       (define result (render-call (lambda () (if task?
                          (begin (unless (runtime-store rt) (mcp-error -32603 "Task storage is not configured"))
                                 (start-workflow-task (tool-descriptor-workflow d) (runtime-store rt) bound (principal-key principal)
                                                      #:state (current-workflow-state) #:responses (current-workflow-responses)
                                                      #:operation-name (tool-descriptor-name d) #:adapters (current-workflow-adapters) #:custodian (runtime-custodian rt)))
                          (invoke-handler)))
                                   (if (tool-descriptor-workflow d) (workflow-executable-fingerprint (tool-descriptor-workflow d) (current-workflow-adapters)) "render/1")))
       (unless (and (hash? result)
                    (or (and (or task? (task-handler? (tool-descriptor-handler d)))
                             (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)
                             (equal? (hash-ref result 'resultType #f) "task"))
                        (and (equal? (hash-ref result 'resultType #f) "complete") (list? (hash-ref result 'content #f)))
                        (and (equal? (hash-ref result 'resultType #f) "input_required")
                             (string? (hash-ref result 'requestState #f)) (hash? (hash-ref result 'inputRequests #f)))))
         (mcp-error -32603 "Handler returned an invalid tool result"))
       (when (equal? (hash-ref result 'resultType) "complete")
         (set! result (embedded-json (hash-set result 'content (expand-content-items (hash-ref result 'content))))))
       (when (and (equal? (hash-ref result 'resultType) "complete") (tool-descriptor-output-schema d) (not (hash-ref result 'isError #f))
                  (or (not (hash-has-key? result 'structuredContent))
                      (not (valid? (tool-descriptor-output-schema d) (hash-ref result 'structuredContent)))))
         (mcp-error -32603 "Tool output failed its declared schema")) result]
      [(completion/complete)
       (define ref (hash-ref params 'ref (hasheq))) (define arg (hash-ref params 'argument (hasheq)))
       (define completion
         (findf (lambda (d)
                  (define target (completion-descriptor-target d))
                  (and (equal? (symbol->string (completion-descriptor-argument d)) (hash-ref arg 'name #f))
                       (cond [(resource-descriptor? target) (and (equal? (hash-ref ref 'type #f) "ref/resource") (equal? (resource-descriptor-uri target) (hash-ref ref 'uri #f)))]
                             [(prompt-descriptor? target) (and (equal? (hash-ref ref 'type #f) "ref/prompt") (equal? (prompt-descriptor-name target) (hash-ref ref 'name #f)))] [else #f])))
                (interface-descriptor-completions iface)))
       (unless completion (mcp-error -32602 "Unknown completion target"))
       (define supplied ((completion-descriptor-handler completion) (hash-ref arg 'value "") (hash-ref params 'context (hasheq))))
       (define result
         (cond [(and (list? supplied) (andmap string? supplied))
                (hasheq 'values (take supplied (min 100 (length supplied))) 'total (length supplied) 'hasMore (> (length supplied) 100))]
               [(and (hash? supplied) (json-value? supplied)
                     (list? (hash-ref supplied 'values #f)) (andmap string? (hash-ref supplied 'values))
                     (<= (length (hash-ref supplied 'values)) 100)
                     (or (not (hash-has-key? supplied 'total)) (rational? (hash-ref supplied 'total)))
                     (or (not (hash-has-key? supplied 'hasMore)) (boolean? (hash-ref supplied 'hasMore)))) supplied]
               [else (mcp-error -32603 "Invalid completion values")]))
       (hasheq 'resultType "complete" 'completion result)]
      [(subscriptions/listen)
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
           (unless ((runtime-authorize rt) principal "tasks/get" (hasheq 'taskId task-id))
             (mcp-error -32001 "Task subscription is not authorized"))
           (get-task (runtime-store rt) task-id (principal-key principal)))
         (set! accepted (hash-set accepted 'taskIds (remove-duplicates ids))))
       (define (notification-authorized? notice)
         (and (or (not (verified-principal? principal))
                  (> (verified-principal-expiry principal) (mcp-current-seconds)))
              (with-handlers ([exn:fail:mcp? (lambda (_) #f)])
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
                              (get-task (runtime-store rt) (hash-ref values 'taskId #f) (principal-key principal))))))))
       (listen-subscription (runtime-subscriptions rt) id principal accepted
         (lambda (notice)
           (when (or (equal? (hash-ref notice 'method #f) "notifications/subscriptions/acknowledged")
                     (notification-authorized? notice))
             (notify notice))))]
      [(tasks/get tasks/update tasks/cancel)
       (unless (runtime-store rt) (mcp-error -32601 "Tasks are not configured"))
       (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks) (mcp-error -32021 "Client Tasks capability is required"
         (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
       (define task-id (hash-ref params 'taskId #f))
       (unless (string? task-id) (mcp-error -32602 "taskId must be a string"))
       (define task-instance (load-instance (runtime-store rt) task-id))
       (define task-tool (and task-instance (resolve-task-operation (interface-descriptor-tools iface) task-instance)))
       (when (and (current-upstream-task-observation)
                  (equal? task-id (car (current-upstream-task-observation)))
                  (not (and task-tool (task-handler? (tool-descriptor-handler task-tool)))))
         (mcp-error -32602 "Task does not have an upstream observation handler"))
       (if (and task-tool (task-handler? (tool-descriptor-handler task-tool)))
           (begin
             ;; Validate ownership before authorization callbacks or upstream I/O.
             (get-task (runtime-store rt) task-id (principal-key principal))
             (unless ((runtime-authorize rt) principal "tools/call"
                      (hasheq 'name (tool-descriptor-name task-tool)
                              'arguments (hash-ref (hash-ref (stored-instance-arguments task-instance) 'params) 'arguments (hasheq))))
               (mcp-error -32001 "Upstream task operation is not authorized"))
             ((task-handler-dispatch (tool-descriptor-handler task-tool)) method task-id params))
       (case (string->symbol method)
         [(tasks/get) (get-task (runtime-store rt) task-id (principal-key principal))]
         [(tasks/cancel) (cancel-task! (runtime-store rt) task-id (principal-key principal))]
         [(tasks/update)
          (define instance (load-instance (runtime-store rt) task-id))
          (unless instance (mcp-error -32602 "Unknown task"))
          (define tool (resolve-task-operation (interface-descriptor-tools iface) instance))
          (unless tool (mcp-error -32603 "Task executable is unavailable"))
          (unless ((runtime-authorize rt) principal "tools/call" (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance)))
            (mcp-error -32001 "Resumed operation is not authorized"))
          (update-task! (tool-descriptor-workflow tool) (runtime-store rt) task-id (principal-key principal) (hash-ref params 'inputResponses (hasheq)) #:adapters (current-workflow-adapters) #:custodian (runtime-custodian rt))]))]
      [(resources/list)
       (listing 'resources (for/list ([d (in-list (interface-descriptor-resources iface))] #:when (null? (resource-descriptor-arguments d)))
                              (hasheq 'name (resource-descriptor-name d) 'uri (resource-descriptor-uri d)
                                      'description (resource-descriptor-description d) 'mimeType (resource-descriptor-mime-type d))))]
      [(resources/templates/list)
       (listing 'resourceTemplates (for/list ([d (in-list (interface-descriptor-resources iface))] #:unless (null? (resource-descriptor-arguments d)))
                                      (hasheq 'name (resource-descriptor-name d) 'uriTemplate (resource-descriptor-uri d) 'mimeType (resource-descriptor-mime-type d))))]
      [(resources/read)
       (define uri (hash-ref params 'uri #f))
       (unless (string? uri) (mcp-error -32602 "Resource URI must be a string"))
       (define matches (filter values (for/list ([d (in-list (interface-descriptor-resources iface))])
                                        (define args ((resource-descriptor-matcher d) uri)) (and args (cons d args)))))
       (unless (= (length matches) 1) (mcp-error -32602 "Unknown or ambiguous resource URI" (hasheq 'uri uri)))
       (define d (caar matches))
       (define args (bind-arguments (resource-descriptor-arguments d) (cdar matches)))
       (define renderer-version (renderer-fingerprint (resource-descriptor-renderer d)))
       (define program
         (and (resource-descriptor-workflow d)
              (workflow-add-fingerprint-suffix (resource-descriptor-workflow d)
                                               (string-append ":renderer:" renderer-version))))
       (define dependencies (change-keys! ((resource-descriptor-depends-on d) args)))
       (define parent (current-resource-snapshots))
       (define bypass? (or program (current-workflow-state) (current-workflow-invocation-key)
                           (hash-has-key? params 'inputResponses)))
       (define (compute)
         (define children (box '()))
         (define content
           (parameterize ([current-resource-snapshots children])
             (render-call
          (lambda ()
            (define value
              (if program
                  (run-domain-workflow program args)
                  (apply (resource-descriptor-handler d) (map (lambda (a) (hash-ref args (argument-name a))) (resource-descriptor-arguments d)))))
            (if (and (resource-descriptor-renderer d) (not (input-required? value)))
                (apply-resource-renderer (resource-descriptor-renderer d) value) value))
          (if program (workflow-executable-fingerprint program (current-workflow-adapters)) (string-append "render/1:renderer:" renderer-version)))))
         (define reads (remove-duplicates (cons uri (append-map resource-snapshot-reads (unbox children)))))
         (define keys (remove-duplicates (append dependencies (append-map resource-snapshot-keys (unbox children)))))
         (define now (cache-clock (runtime-cache rt)))
         (define expires
           (apply min (+ now (if bypass? 0 (resource-descriptor-ttl-ms d)))
                  (if (verified-principal? principal)
                      (+ now (max 0 (* 1000 (- (verified-principal-expiry principal) (mcp-current-seconds))))) +inf.0)
                  (map resource-snapshot-expires (unbox children))))
         (define limited-ttl (max 0 (inexact->exact (floor (- expires now)))))
         (resource-snapshot
           (if (input-required? content) content
               (hash-set (cache (hasheq 'resultType "complete" 'contents
                                      (presentation-contents content uri (resource-descriptor-mime-type d)))) 'ttlMs limited-ttl))
           reads keys expires))
       (define snapshot
         (if bypass? (compute)
             (cache-ref! (runtime-cache rt)
                         (cache-partition (principal-key principal)
                           (list (runtime-cache-namespace rt) ((runtime-cache-context rt) principal) (json->string caps)
                                 (json->string (for/hasheq ([(k v) (in-hash args)] #:unless (missing? v)) (values k v)))
                                 (json->string dependencies)))
                         uri resource-snapshot-keys
                         (lambda (s) (hash-ref (resource-snapshot-result s) 'ttlMs 0)) compute
                         #:cacheable? (lambda (s) (equal? (hash-ref (resource-snapshot-result s) 'resultType #f) "complete"))
                         #:usable? (lambda (s) (andmap (lambda (child-uri)
                            ((runtime-authorize rt) principal "resources/read" (hasheq 'uri child-uri '_meta meta)))
                            (resource-snapshot-reads s)))
                         #:on-hit snapshot-with-ttl #:expires-at resource-snapshot-expires
                         #:on-invalidated (lambda (s) (struct-copy resource-snapshot s
                           [result (if (input-required? (resource-snapshot-result s)) (resource-snapshot-result s)
                                       (hash-set (resource-snapshot-result s) 'ttlMs 0))]
                           [expires (cache-clock (runtime-cache rt))])))))
       (when parent (set-box! parent (cons snapshot (unbox parent))))
       (resource-snapshot-result snapshot)]
      [(prompts/list)
       (listing 'prompts (for/list ([d (in-list (interface-descriptor-prompts iface))])
                            (hasheq 'name (prompt-descriptor-name d) 'description (prompt-descriptor-description d)
                                    'arguments (for/list ([a (in-list (prompt-descriptor-arguments d))])
                                                 (hasheq 'name (symbol->string (argument-name a)) 'required (not (argument-optional? a)))))))]
      [(prompts/get)
       (define d (lookup (interface-descriptor-prompts iface) prompt-descriptor-name 'name))
       (define input (hash-ref params 'arguments (hasheq)))
       (unless (and (hash? input) (for/and ([value (in-hash-values input)]) (string? value))) (mcp-error -32602 "Prompt arguments must be strings"))
       (define arguments (bind-arguments (prompt-descriptor-arguments d) input))
       (define program
         (and (prompt-descriptor-workflow d)
              (workflow-add-fingerprint-suffix (prompt-descriptor-workflow d)
                                               (string-append ":prompt-codecs:" (prompt-codec-fingerprint d)))))
       (define messages (render-call (lambda () (if program
                            (run-domain-workflow program arguments)
                            ((prompt-descriptor-handler d) arguments)))
                                     (if program (workflow-executable-fingerprint program (current-workflow-adapters)) (string-append "render/1:" (prompt-codec-fingerprint d)))))
       (cond [(input-required? messages) messages]
             [(and (hash? messages) (equal? (hash-ref messages 'resultType #f) "complete")
                   (list? (hash-ref messages 'messages #f)))
              (hash-set messages 'messages (expand-prompt-messages (hash-ref messages 'messages)))]
             [else (unless (list? messages) (mcp-error -32603 "Prompt renderer must return messages"))
                   (hasheq 'resultType "complete" 'messages (expand-prompt-messages messages))])]
      [else (mcp-error -32601 "Method not found")])) )
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

;; An explicit local action after recovery, never an automatic wire retry.
(define/clock (retry-runtime-task! rt id #:principal principal #:capabilities supplied-caps)
  (define caps (string->json (json->string supplied-caps)))
  (define store (runtime-store rt))
  (unless store (mcp-error -32601 "Tasks are not configured"))
  (validate-request-meta (hasheq '_meta (request-meta #:capabilities caps)))
  (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)
    (mcp-error -32021 "Client Tasks capability is required"
      (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
  (define identity (principal-key principal))
  (get-task store id identity)
  (define instance (load-instance store id))
  (define tool (resolve-task-operation (interface-descriptor-tools (runtime-interface rt)) instance))
  (unless tool (mcp-error -32001 "Task operation is absent from this interface"))
  (unless (tool-descriptor-workflow tool)
    (mcp-error -32602 "Upstream task recovery requires a separately observed upstream outcome"))
  (when (and (ormap (lambda (stage) (memq (workflow-stage-kind stage) '(input input-group)))
                    (workflow-descriptor-stages (tool-descriptor-workflow tool)))
             (not (hash-has-key? caps 'elicitation)))
    (mcp-error -32021 "Client elicitation capability is required"
      (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
  (define (authorize)
    (unless (and (or (not (verified-principal? principal)) (> (verified-principal-expiry principal) (mcp-current-seconds)))
                 ((runtime-authorize rt) principal "tasks/get" (hasheq 'taskId id))
                 ((runtime-authorize rt) principal "tools/call"
                   (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance))))
      (mcp-error -32001 "Repaired task execution is not authorized"))
    (current-request-context (request-context principal caps #f (current-cancelled?) void)))
  (parameterize ([current-request-context #f]
                 [current-workflow-change-publisher (lambda () (runtime-drain-changes! rt))]
                 [current-task-notify (task-notifier rt)])
    (retry-recovered-task! (tool-descriptor-workflow tool) store id identity
      #:adapters (operation-adapters rt tool) #:custodian (runtime-custodian rt) #:authorize authorize)))
