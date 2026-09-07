#lang racket/base
(require racket/list racket/string "descriptor.rkt" "schema.rkt" "json.rkt" "error.rkt" "presentation.rkt" "uri-template.rkt" "completion.rkt")
(provide capture-snapshot make-upstream-interface check-upstream-compatibility! (struct-out upstream-template-adapter))
(define methods '("server/discover" "tools/list" "resources/list" "resources/templates/list" "prompts/list"))
(define (result! outcome)
  (when (hash-has-key? outcome 'error) (mcp-error -32603 "Upstream request failed" (hash-ref outcome 'error)))
  (hash-ref outcome 'result outcome))
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
(struct upstream-template-adapter (arguments matcher) #:transparent)
(define (make-upstream-interface supplied-snapshot request #:templates [templates (hash)])
  (define snapshot (string->json (json->string supplied-snapshot)))
  (define verified? #f) (define lock (make-semaphore 1))
  (define (invoke method params)
    (call-with-semaphore lock (lambda () (unless verified? (check-upstream-compatibility! snapshot request) (set! verified? #t))))
    (define result (result! (request method params)))
    (unless (equal? (hash-ref result 'resultType "complete") "complete")
      (mcp-error -32603 "Upstream MRTR/Tasks requires a durable handle-translation adapter, which is not yet implemented")) (hash-set result 'resultType "complete"))
  (define (build-resource wire uri arguments matcher)
    (make-resource (hash-ref wire 'name) uri
      (lambda supplied-values
        (define remote-uri (uri-template-expand uri
          (for/hasheq ([argument (in-list arguments)] [value (in-list supplied-values)])
            (values (argument-name argument) value))))
        (define result (invoke "resources/read" (hasheq 'uri remote-uri)))
        (apply resource-contents
          (for/list ([content (in-list (hash-ref result 'contents))])
            (resource-content (hash-set content 'uri (remap-uri (hash-ref content 'uri)))))))
      #:description (hash-ref wire 'description "") #:mime-type (hash-ref wire 'mimeType #f)
      #:arguments arguments #:matcher matcher))
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
        (lambda (bound)
          (define result (invoke "prompts/get" (hasheq 'name name 'arguments
            (for/hasheq ([(key value) (in-hash bound)] #:unless (missing? value)) (values key value)))))
          (hash-set result 'messages
            (for/list ([message (in-list (hash-ref result 'messages))])
              (hash-set message 'content (remap-content (hash-ref message 'content))))))
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
      (make-tool (hash-ref wire 'name) '()
                 (lambda (bound)
                   (define result (invoke "tools/call" (hasheq 'name (hash-ref wire 'name) 'arguments bound)))
                   (hash-set result 'content (map remap-content (hash-ref result 'content))))
                 #:description (hash-ref wire 'description "") #:output (hash-ref wire 'outputSchema #f)
                 #:annotations (hash-ref wire 'annotations (hasheq))
                 #:input-schema schema #:raw? #t))))
