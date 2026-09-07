#lang racket/base
(require racket/list racket/match net/base64 "descriptor.rkt" "schema.rkt" "json.rkt" "workflow.rkt" "tasks.rkt" "storage.rkt" "subscription.rkt" "error.rkt" "completion.rkt" "authorization.rkt")
(provide protocol-version make-runtime (struct-out runtime) dispatch dispatch-message
         (struct-out exn:fail:mcp) mcp-error request-meta validate-request-meta)
(define protocol-version "2026-07-28")
(define current-embedding-stack (make-parameter '()))
(struct runtime (interface authorize store adapters custodian subscriptions) #:transparent)
(define (make-runtime interface #:authorize [authorize (lambda (principal method params) #t)] #:store [store #f] #:adapters [adapters (hasheq)])
  (runtime interface authorize store adapters (make-custodian) (make-subscription-hub)))
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
  (define version (hash-ref meta 'io.modelcontextprotocol/protocolVersion))
  (unless (or (not version?) (equal? version protocol-version))
    (mcp-error -32022 "Unsupported protocol version" (hasheq 'supported (list protocol-version) 'requested version))) meta)
(define (cache result) (hash-set* result 'ttlMs 0 'cacheScope "private"))
(define (complete key xs) (cache (hasheq 'resultType "complete" key xs)))
(define (tool-wire d)
  (define base (hasheq 'name (tool-descriptor-name d) 'description (tool-descriptor-description d)
                       'inputSchema (tool-descriptor-input-schema d) 'annotations (tool-descriptor-annotations d)))
  (if (tool-descriptor-output-schema d) (hash-set base 'outputSchema (tool-descriptor-output-schema d)) base))
(define (dispatch rt method params #:principal [principal 'local] #:id [id #f] #:notify [notify void])
  (define meta (validate-request-meta params))
  (define caps (hash-ref meta 'io.modelcontextprotocol/clientCapabilities missing))
  (unless (hash? caps) (mcp-error -32602 "clientCapabilities must be an object"))
  (unless ((runtime-authorize rt) principal method params) (mcp-error -32001 "Operation is not authorized"))
  (define iface (runtime-interface rt))
  (when (or (and (member method '("prompts/list" "prompts/get")) (null? (interface-descriptor-prompts iface)))
            (and (member method '("resources/list" "resources/templates/list" "resources/read")) (null? (interface-descriptor-resources iface)))
            (and (member method '("tools/list" "tools/call")) (null? (interface-descriptor-tools iface))))
    (mcp-error -32601 "Capability is not installed"))
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
                      (hasheq 'type "resource" 'resource (car (hash-ref result 'contents)))))]
                 [current-workflow-store (runtime-store rt)] [current-workflow-adapters (runtime-adapters rt)]
                 [current-workflow-state (hash-ref params 'requestState #f)] [current-workflow-responses (hash-ref params 'inputResponses (hasheq))])
    (case (string->symbol method)
      [(server/discover)
       (define server (interface-descriptor-server iface))
       (define base-capabilities
         (for/fold ([c (hasheq)]) ([k '(tools resources prompts)] [xs (list (interface-descriptor-tools iface) (interface-descriptor-resources iface) (interface-descriptor-prompts iface))])
           (if (null? xs) c (hash-set c k (hasheq)))))
       (define capabilities
         (let* ([c (if (pair? (interface-descriptor-completions iface)) (hash-set base-capabilities 'completions (hasheq)) base-capabilities)]
                [c (if (and (runtime-store rt) (ormap tool-descriptor-workflow (interface-descriptor-tools iface)))
                       (hash-set c 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))) c)]) c))
       (cache (hasheq 'resultType "complete" 'supportedVersions (list protocol-version) 'capabilities capabilities
                      'instructions (if server (server-descriptor-instructions server) "")
                      '_meta (hasheq 'io.modelcontextprotocol/serverInfo
                                    (hasheq 'name (if server (server-descriptor-name server) "mcp") 'version (if server (server-descriptor-version server) "0")))))]
      [(tools/list) (complete 'tools (map tool-wire (interface-descriptor-tools iface)))]
      [(tools/call)
       (define d (lookup (interface-descriptor-tools iface) tool-descriptor-name 'name))
       (define args (hash-ref params 'arguments (hasheq)))
       (unless (valid? (tool-descriptor-input-schema d) args) (mcp-error -32602 "Invalid tool arguments"))
       (define bound (if (tool-descriptor-raw? d) args (bind-arguments (tool-descriptor-arguments d) args)))
       (define task? (eq? (tool-descriptor-execution d) 'task))
       (when (and task? (not (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks)))
         (mcp-error -32021 "Client Tasks capability is required" (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))))
       (when (and (tool-descriptor-workflow d)
                  (ormap (lambda (s) (eq? (workflow-stage-kind s) 'input)) (workflow-descriptor-stages (tool-descriptor-workflow d)))
                  (not (hash-has-key? caps 'elicitation))) (mcp-error -32021 "Client elicitation capability is required" (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
       (define result (if task?
                          (begin (unless (runtime-store rt) (mcp-error -32603 "Task storage is not configured"))
                                 (start-workflow-task (tool-descriptor-workflow d) (runtime-store rt) bound (principal-key principal) #:adapters (runtime-adapters rt) #:custodian (runtime-custodian rt)))
                          ((tool-descriptor-handler d) bound)))
       (unless (and (hash? result)
                    (or (and task? (equal? (hash-ref result 'resultType #f) "task"))
                        (and (equal? (hash-ref result 'resultType #f) "complete") (list? (hash-ref result 'content #f)))
                        (and (equal? (hash-ref result 'resultType #f) "input_required")
                             (string? (hash-ref result 'requestState #f)) (hash? (hash-ref result 'inputRequests #f)))))
         (mcp-error -32603 "Handler returned an invalid tool result"))
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
                       (cond [(resource-descriptor? target) (equal? (resource-descriptor-uri target) (hash-ref ref 'uri #f))]
                             [(prompt-descriptor? target) (equal? (prompt-descriptor-name target) (hash-ref ref 'name #f))] [else #f])))
                (interface-descriptor-completions iface)))
       (unless completion (mcp-error -32602 "Unknown completion target"))
       (define values ((completion-descriptor-handler completion) (hash-ref arg 'value "") (hash-ref params 'context (hasheq))))
       (unless (and (list? values) (andmap string? values)) (mcp-error -32603 "Invalid completion values"))
       (hasheq 'resultType "complete" 'completion (hasheq 'values (take values (min 100 (length values))) 'total (length values) 'hasMore (> (length values) 100)))]
      [(subscriptions/listen)
       (define requested (hash-ref params 'notifications #f))
       (unless (hash? requested) (mcp-error -32602 "notifications filter must be an object"))
       (define accepted
         (for/fold ([accepted (hasheq)]) ([key '(toolsListChanged promptsListChanged resourcesListChanged resourceSubscriptions)]
                                         [available (list (pair? (interface-descriptor-tools iface)) (pair? (interface-descriptor-prompts iface)) (pair? (interface-descriptor-resources iface)) (pair? (interface-descriptor-resources iface)))])
           (if (and available (hash-ref requested key #f)) (hash-set accepted key (hash-ref requested key)) accepted)))
       (listen-subscription (runtime-subscriptions rt) id principal accepted notify)]
      [(tasks/get tasks/update tasks/cancel)
       (unless (runtime-store rt) (mcp-error -32601 "Tasks are not configured"))
       (unless (hash-has-key? (hash-ref caps 'extensions (hasheq)) 'io.modelcontextprotocol/tasks) (mcp-error -32021 "Client Tasks capability is required"))
       (define task-id (hash-ref params 'taskId #f))
       (unless (string? task-id) (mcp-error -32602 "taskId must be a string"))
       (case (string->symbol method)
         [(tasks/get) (get-task (runtime-store rt) task-id (principal-key principal))]
         [(tasks/cancel) (cancel-task! (runtime-store rt) task-id (principal-key principal))]
         [(tasks/update)
          (define instance (load-instance (runtime-store rt) task-id))
          (unless instance (mcp-error -32602 "Unknown task"))
          (define tool (findf (lambda (d) (and (tool-descriptor-workflow d) (equal? (stored-instance-operation instance) (string-append "task:" (workflow-descriptor-name (tool-descriptor-workflow d)))))) (interface-descriptor-tools iface)))
          (unless tool (mcp-error -32603 "Task executable is unavailable"))
          (unless ((runtime-authorize rt) principal "tools/call" (hasheq 'name (tool-descriptor-name tool) 'arguments (stored-instance-arguments instance)))
            (mcp-error -32001 "Resumed operation is not authorized"))
          (update-task! (tool-descriptor-workflow tool) (runtime-store rt) task-id (principal-key principal) (hash-ref params 'inputResponses (hasheq)) #:adapters (runtime-adapters rt) #:custodian (runtime-custodian rt))])]
      [(resources/list)
       (complete 'resources (for/list ([d (in-list (interface-descriptor-resources iface))] #:when (null? (resource-descriptor-arguments d)))
                              (hasheq 'name (resource-descriptor-name d) 'uri (resource-descriptor-uri d)
                                      'description (resource-descriptor-description d) 'mimeType (resource-descriptor-mime-type d))))]
      [(resources/templates/list)
       (complete 'resourceTemplates (for/list ([d (in-list (interface-descriptor-resources iface))] #:unless (null? (resource-descriptor-arguments d)))
                                      (hasheq 'name (resource-descriptor-name d) 'uriTemplate (resource-descriptor-uri d) 'mimeType (resource-descriptor-mime-type d))))]
      [(resources/read)
       (define uri (hash-ref params 'uri #f))
       (unless (string? uri) (mcp-error -32602 "Resource URI must be a string"))
       (define matches (filter values (for/list ([d (in-list (interface-descriptor-resources iface))])
                                        (define args ((resource-descriptor-matcher d) uri)) (and args (cons d args)))))
       (unless (= (length matches) 1) (mcp-error -32602 "Unknown or ambiguous resource URI"))
       (define d (caar matches))
       (define args (bind-arguments (resource-descriptor-arguments d) (cdar matches)))
       (define content (apply (resource-descriptor-handler d) (map (lambda (a) (hash-ref args (argument-name a))) (resource-descriptor-arguments d))))
       (unless (or (string? content) (bytes? content)) (mcp-error -32603 "Resource renderer must return text or bytes"))
       (cache (hasheq 'resultType "complete" 'contents
                      (list (hasheq 'uri uri 'mimeType (resource-descriptor-mime-type d)
                                    (if (bytes? content) 'blob 'text) (if (bytes? content) (bytes->string/utf-8 (base64-encode content #"")) content)))))]
      [(prompts/list)
       (complete 'prompts (for/list ([d (in-list (interface-descriptor-prompts iface))])
                            (hasheq 'name (prompt-descriptor-name d) 'description (prompt-descriptor-description d)
                                    'arguments (for/list ([a (in-list (prompt-descriptor-arguments d))])
                                                 (hasheq 'name (symbol->string (argument-name a)) 'required (not (argument-optional? a)))))))]
      [(prompts/get)
       (define d (lookup (interface-descriptor-prompts iface) prompt-descriptor-name 'name))
       (define input (hash-ref params 'arguments (hasheq)))
       (unless (and (hash? input) (for/and ([value (in-hash-values input)]) (string? value))) (mcp-error -32602 "Prompt arguments must be strings"))
       (hasheq 'resultType "complete" 'messages ((prompt-descriptor-handler d) (bind-arguments (prompt-descriptor-arguments d) (hash-ref params 'arguments (hasheq)))))]
      [else (mcp-error -32601 "Method not found")])) )
(define (dispatch-message rt message #:principal [principal 'local] #:notify [notify void])
  (define id (if (hash? message) (hash-ref message 'id missing) missing))
  (define (error-response e)
    (define detail (hasheq 'code (if (exn:fail:mcp? e) (exn:fail:mcp-code e) -32603)
                          'message (if (exn:fail:mcp? e) (exn-message e) "Internal error")))
    (define body (hasheq 'jsonrpc "2.0" 'error (if (and (exn:fail:mcp? e) (exn:fail:mcp-data e)) (hash-set detail 'data (exn:fail:mcp-data e)) detail)))
    (if (or (missing? id) (not (or (string? id) (rational? id)))) body (hash-set body 'id id)))
  (with-handlers ([exn:fail? error-response])
    (unless (and (hash? message) (equal? (hash-ref message 'jsonrpc #f) "2.0")
                 (string? (hash-ref message 'method #f))
                 (not (hash-has-key? message 'result)) (not (hash-has-key? message 'error))
                 (or (missing? id) (string? id) (rational? id)))
      (mcp-error -32600 "Invalid Request"))
    (if (missing? id) #f
        (hasheq 'jsonrpc "2.0" 'id id 'result (dispatch rt (hash-ref message 'method) (hash-ref message 'params (hasheq)) #:principal principal #:id id #:notify notify)))))
