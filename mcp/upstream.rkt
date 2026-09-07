#lang racket/base
(require racket/list racket/string "descriptor.rkt" "schema.rkt" "json.rkt" "error.rkt" "presentation.rkt" "uri-template.rkt" "completion.rkt"
         "upstream-bridge.rkt" (submod "upstream-bridge.rkt" private) "private/upstream-task.rkt"
         "workflow.rkt" (only-in "storage.rkt" opaque-handle) (only-in "tasks.rkt" current-task-notify) "authorization.rkt" "private/handler-info.rkt" "private/task-observation.rkt")
(provide capture-snapshot make-upstream-interface upstream-resource-change-keys check-upstream-compatibility! recover-upstream-task! retry-upstream-task! (struct-out upstream-template-adapter))
(provide (all-from-out "upstream-bridge.rkt"))
(define methods '("server/discover" "tools/list" "resources/list" "resources/templates/list" "prompts/list"))
(define (result! outcome)
  (when (and (not (hash-has-key? outcome 'resultType)) (hash-has-key? outcome 'error)) (mcp-error -32603 "Upstream request failed" (hash-ref outcome 'error)))
  (if (hash-has-key? outcome 'resultType) outcome (hash-ref outcome 'result outcome)))
(define (capture-snapshot request)
  (define discovery (result! (request "server/discover" (hasheq))))
  (define capabilities (hash-ref discovery 'capabilities (hasheq)))
  (for/hasheq ([method (in-list methods)])
    (define key (case (string->symbol method) [(tools/list) 'tools] [(resources/list) 'resources] [(resources/templates/list) 'resourceTemplates] [(prompts/list) 'prompts] [else #f]))
    (define capability (case (string->symbol method) [(tools/list) 'tools] [(prompts/list) 'prompts] [else 'resources]))
    (define result (cond [(not key) discovery]
                         [(hash-has-key? capabilities capability) (result! (request method (hasheq)))]
                         [else (hasheq 'resultType "complete" key '() 'ttlMs 0 'cacheScope "private")]))
    (define all
      (if (not key) result
          (let loop ([page result] [items '()] [seen '()])
            (define combined (append items (hash-ref page key)))
            (define next (hash-ref page 'nextCursor #f))
            (cond [(not next) (hash-set (hash-remove result 'nextCursor) key combined)]
                  [(member next seen) (error 'capture-snapshot "upstream repeated a pagination cursor")]
                  [else (loop (result! (request method (hasheq 'cursor next))) combined (cons next seen))]))))
    (values (string->symbol method) all)))
(define (check-upstream-compatibility! snapshot request)
  (define fresh (capture-snapshot request))
  (for ([field '(supportedVersions capabilities)])
    (unless (equal? (hash-ref (hash-ref snapshot 'server/discover) field)
                    (hash-ref (hash-ref fresh 'server/discover) field))
      (error 'upstream "pinned discovery changed; refresh and review the snapshot")))
  (for ([method '(tools/list prompts/list resources/list resources/templates/list)])
    (define field (case method [(tools/list) 'tools] [(prompts/list) 'prompts] [(resources/list) 'resources] [else 'resourceTemplates]))
    (unless (equal? (hash-ref (hash-ref snapshot method) field) (hash-ref (hash-ref fresh method) field))
      (error 'upstream "pinned interface changed; refresh and review the snapshot"))) #t)
(define (retry-upstream-task! bridge store snapshot request id #:principal principal #:credential-id credential
                              #:authorize [authorize void])
  (unless (and (procedure? request) (procedure-arity-includes? request 2))
    (raise-argument-error 'retry-upstream-task! "request procedure accepting method and parameters" request))
  (retry-upstream-task/core! bridge store snapshot request id principal credential authorize
    (lambda () (check-upstream-compatibility! snapshot request))))
(struct upstream-template-adapter (arguments matcher) #:transparent)
(define (upstream-resource-change-keys interface uri)
  (unless (interface-descriptor? interface)
    (raise-argument-error 'upstream-resource-change-keys "interface-descriptor?" interface))
  (unless (string? uri) (raise-argument-error 'upstream-resource-change-keys "string?" uri))
  (define matches
    (filter values
      (for/list ([resource (in-list (interface-descriptor-resources interface))])
        (define arguments ((resource-descriptor-matcher resource) uri))
        (and arguments (cons resource arguments)))))
  (unless (= (length matches) 1)
    (error 'upstream-resource-change-keys "expected one resource matching URI ~s; found ~a" uri (length matches)))
  (define resource (caar matches))
  (define arguments (bind-arguments (resource-descriptor-arguments resource) (cdar matches)))
  (define keys ((resource-descriptor-depends-on resource) arguments))
  (unless (and (list? keys) (pair? keys) (json-value? keys)
               (andmap (lambda (key) (and (list? key) (= (length key) 3)
                                          (equal? (car key) "mcp/upstream-resource"))) keys))
    (error 'upstream-resource-change-keys "resource does not declare upstream change keys"))
  keys)
(define (make-upstream-interface supplied-snapshot request #:templates [templates (hash)] #:bridge [bridge #f])
  (unless (or (not bridge) (upstream-bridge? bridge)) (raise-argument-error 'make-upstream-interface "upstream-bridge? or #f" bridge))
  (define snapshot (string->json (json->string supplied-snapshot)))
  ;; Each installed upstream has a separate freshness domain, even when two
  ;; servers publish identical snapshots and URI spellings. Views retain this
  ;; closure; no upstream credential or handle appears in a dependency key.
  (define freshness-source (opaque-handle))
  (define (durable-handler procedure) (if bridge (stateful-handler procedure) procedure))
  (define tasks? (and bridge (hash-has-key?
    (hash-ref (hash-ref (hash-ref snapshot 'server/discover) 'capabilities) 'extensions (hasheq))
    'io.modelcontextprotocol/tasks)))
  (define verified (make-hash)) (define lock (make-semaphore 1))
  (define (verify-for credential)
    (call-with-semaphore lock
      (lambda () (unless (hash-ref verified credential #f)
                   (check-upstream-compatibility! snapshot request) (hash-set! verified credential #t)))))
  (define (invoke method params [task-source #f])
    (define context (current-request-context))
    (define credential (and bridge ((upstream-bridge-credential-id bridge) (request-context-principal context))))
    (define (verify) (verify-for credential))
    (define durable? (and bridge (member method '("tools/call" "resources/read" "prompts/get"))))
    (define result
      (result!
       (if durable?
           (parameterize ([current-upstream-task-result
                           (and task-source
                             (lambda (parent capabilities)
                               (adopt-upstream-task! bridge (current-workflow-store) snapshot parent task-source capabilities)))])
           (bridge-upstream-request bridge (current-workflow-store) snapshot request method params
                                    #:principal (principal-key (request-context-principal context)) #:credential-id credential
                                    #:state (current-workflow-state) #:responses (current-workflow-responses)
                                    #:capabilities (request-context-capabilities context) #:key (current-workflow-invocation-key)
                                    #:cancelled? (request-context-cancelled? context) #:verify verify))
           (begin (verify) (request method params)))))
    (unless (or (equal? (hash-ref result 'resultType "complete") "complete")
                (and durable? (equal? (hash-ref result 'resultType #f) "input_required"))
                (and task-source (equal? (hash-ref result 'resultType #f) "task")))
      (mcp-error -32603 "Upstream outcome requires a supported durable translation for this operation"))
    (hash-set result 'resultType (hash-ref result 'resultType "complete")))
  (define (pending? result) (member (hash-ref result 'resultType #f) '("input_required" "task")))
  (define (build-resource wire uri arguments matcher)
    (make-resource (hash-ref wire 'name) uri
      (durable-handler (lambda supplied-values
        (define remote-uri (uri-template-expand uri
          (for/hasheq ([argument (in-list arguments)] [value (in-list supplied-values)])
            (values (argument-name argument) value))))
        (define result (invoke "resources/read" (hasheq 'uri remote-uri)))
        (if (pending? result) result
        (apply resource-contents
          (for/list ([content (in-list (hash-ref result 'contents))])
            (resource-content (hash-set content 'uri (remap-uri (hash-ref content 'uri)))))))))
      #:description (hash-ref wire 'description "") #:mime-type (hash-ref wire 'mimeType #f)
      #:arguments arguments #:matcher matcher
      #:depends-on
      (lambda (bound)
        (list (list "mcp/upstream-resource" freshness-source (uri-template-expand uri bound))))))
  (define resources
    (append
     (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'resources/list) 'resources))])
       (build-resource wire (hash-ref wire 'uri) '() #f))
     (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'resources/templates/list) 'resourceTemplates))])
       (define uri (hash-ref wire 'uriTemplate))
       (define adapter (hash-ref templates uri #f))
       (when (and adapter (not (upstream-template-adapter? adapter)))
         (error 'make-upstream-interface "Expected an upstream-template-adapter for ~a" uri))
       (define arguments
         (if adapter (upstream-template-adapter-arguments adapter)
             (for/list ([name (in-list (uri-template-variables uri))])
               (argument name String #f #f))))
       (build-resource wire uri arguments
         (if adapter (upstream-template-adapter-matcher adapter) (uri-template-matcher uri))))))
  (define (local-reference uri)
    (define matches
      (filter values
        (for/list ([resource (in-list resources)])
          (define matched ((resource-descriptor-matcher resource) uri))
          (and matched (cons resource matched)))))
    (when (> (length matches) 1)
      (error 'upstream "ambiguous resource reference: ~a" uri))
    (and (pair? matches)
         (let* ([resource (caar matches)]
                [arguments (bind-arguments (resource-descriptor-arguments resource) (cdar matches))])
           (resource-ref resource
             (for/list ([argument (in-list (resource-descriptor-arguments resource))])
               (hash-ref arguments (argument-name argument)))))))
  (define (remap-uri uri)
    (define ref (local-reference uri))
    (if ref (resource-uri ref) uri))
  (define (remap-content content)
    (case (string->symbol (hash-ref content 'type))
      [(resource) (hash-set content 'resource
                   (hash-set (hash-ref content 'resource) 'uri
                     (remap-uri (hash-ref (hash-ref content 'resource) 'uri))))]
      [(resource_link)
       (define ref (local-reference (hash-ref content 'uri)))
       (if ref (hash-set* content 'uri (resource-uri ref) 'name (hash-ref (link ref) 'name)) content)]
      [else content]))
  (define prompts
    (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'prompts/list) 'prompts))])
      (define name (hash-ref wire 'name))
      (define arguments
        (for/list ([arg (in-list (hash-ref wire 'arguments '()))])
          (argument (string->symbol (hash-ref arg 'name)) String (not (hash-ref arg 'required #f)) #f)))
      (make-prompt name arguments
        (durable-handler (lambda (bound)
          (define result (invoke "prompts/get" (hasheq 'name name 'arguments
            (for/hasheq ([(key value) (in-hash bound)] #:unless (missing? value)) (values key value)))))
          (if (pending? result) result
          (hash-set result 'messages
            (for/list ([message (in-list (hash-ref result 'messages))])
              (hash-set message 'content (remap-content (hash-ref message 'content))))))))
        #:description (hash-ref wire 'description ""))))
  (define completions
    (if (hash-has-key? (hash-ref (hash-ref snapshot 'server/discover) 'capabilities) 'completions)
        (append-map
          (lambda (target)
            (define resource? (resource-descriptor? target))
            (define arguments (if resource? (resource-descriptor-arguments target) (prompt-descriptor-arguments target)))
            (define ref (if resource?
                            (hasheq 'type "ref/resource" 'uri (resource-descriptor-uri target))
                            (hasheq 'type "ref/prompt" 'name (prompt-descriptor-name target))))
            (for/list ([argument (in-list arguments)])
              (completion-descriptor target (argument-name argument)
                (lambda (prefix context)
                  (hash-ref (invoke "completion/complete"
                    (hasheq 'ref ref 'argument (hasheq 'name (symbol->string (argument-name argument)) 'value prefix)
                            'context context)) 'completion)))))
          (append resources prompts))
        '()))
  (make-interface #:resources resources #:prompts prompts #:completions completions
    #:tools
    (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'tools/list) 'tools))])
      (define schema (hash-ref wire 'inputSchema)) (check-schema! schema)
      (define source (and tasks? (hasheq 'bridge (upstream-bridge-identity bridge) 'name (hash-ref wire 'name))))
      (define (handler bound)
        (define result (invoke "tools/call" (hasheq 'name (hash-ref wire 'name) 'arguments bound) source))
        (if (pending? result) result (hash-set result 'content (map remap-content (hash-ref result 'content)))))
      (define (translate-task-detail result)
        (if (equal? (hash-ref result 'status #f) "completed")
            (let ([value (hash-ref result 'result)])
              (unless (and (equal? (hash-ref value 'resultType #f) "complete")
                           (list? (hash-ref value 'content #f))
                           (or (hash-ref value 'isError #f) (not (hash-has-key? wire 'outputSchema))
                               (and (hash-has-key? value 'structuredContent)
                                    (valid? (hash-ref wire 'outputSchema) (hash-ref value 'structuredContent)))))
                (mcp-error -32603 "Upstream task result failed its tool contract"))
              (hash-set result 'result (hash-set value 'content (map remap-content (hash-ref value 'content))))) result))
      (define (task-dispatch method id params)
        (define context (current-request-context))
        (define principal (request-context-principal context))
        (define credential ((upstream-bridge-credential-id bridge) principal))
        (define notify (current-task-notify))
        (define observation (current-upstream-task-observation))
        (define target (and observation (equal? id (car observation))
                            (task-subscription-target? (cdr observation)) (cdr observation)))
        (define result
          (if target
              (begin
                (unless (equal? (fingerprint bridge snapshot)
                                (fingerprint bridge (task-subscription-target-snapshot target)))
                  (mcp-error -32602 "Subscription snapshot does not match the installed upstream interface"))
                (hasheq 'remoteId
                  (upstream-task-remote-id bridge (current-workflow-store)
                    snapshot id (principal-key principal) credential source)))
              (parameterize ([current-task-notify (lambda (who detail) (notify who (translate-task-detail detail)))])
            (upstream-task-request bridge (current-workflow-store) snapshot request source method id
              #:principal (principal-key principal) #:credential-id credential
              #:responses (hash-ref params 'inputResponses (hasheq)) #:capabilities (request-context-capabilities context)
              #:observed (and (equal? method "tasks/get") observation (equal? id (car observation)) (cdr observation))
              #:validate-detail (lambda (detail) (translate-task-detail detail) (void))
              #:verify (lambda () (verify-for credential)) #:cancelled? (request-context-cancelled? context)))))
        (translate-task-detail result))
      (make-tool (hash-ref wire 'name) '()
                 (if tasks? (task-handler handler (lambda (instance) (upstream-task-matches? instance source)) task-dispatch)
                     (durable-handler handler))
                 #:description (hash-ref wire 'description "") #:output (hash-ref wire 'outputSchema missing)
                 #:annotations (hash-ref wire 'annotations (hasheq))
                 #:input-schema schema #:raw? #t))))
