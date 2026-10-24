#lang racket/base
(require "runtime-state.rkt"
         "handler-info.rkt"
         "request-meta.rkt"
         "pagination.rkt"
         "../descriptor.rkt"
         "../authorization.rkt"
         "../json.rkt")
(provide dispatch-discovery)
(define (cache result) (hash-set* result 'ttlMs 0 'cacheScope "private"))
(define (tool-wire d)
  (define base (hasheq 'name (tool-descriptor-name d) 'description (tool-descriptor-description d)
                       'inputSchema (tool-descriptor-input-schema d) 'annotations (tool-descriptor-annotations d)))
  (if (tool-descriptor-output-schema d) (hash-set base 'outputSchema (tool-descriptor-output-schema d)) base))
(define (dispatch-discovery rt method params)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (define (listing key items)
    (paginate (runtime-pagination rt) key items
              (list method (principal-key principal) ((runtime-cache-context rt) principal)
                    (json->string caps) (json->string (hash-remove (hash-remove params '_meta) 'cursor)))
              (hash-ref params 'cursor missing)))
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
    [(resources/list)
     (listing 'resources (for/list ([d (in-list (interface-descriptor-resources iface))] #:when (null? (resource-descriptor-arguments d)))
                            (hasheq 'name (resource-descriptor-name d) 'uri (resource-descriptor-uri d)
                                    'description (resource-descriptor-description d) 'mimeType (resource-descriptor-mime-type d))))]
    [(resources/templates/list)
     (listing 'resourceTemplates (for/list ([d (in-list (interface-descriptor-resources iface))] #:unless (null? (resource-descriptor-arguments d)))
                                    (hasheq 'name (resource-descriptor-name d) 'uriTemplate (resource-descriptor-uri d) 'mimeType (resource-descriptor-mime-type d))))]
    [(prompts/list)
     (listing 'prompts (for/list ([d (in-list (interface-descriptor-prompts iface))])
                          (hasheq 'name (prompt-descriptor-name d) 'description (prompt-descriptor-description d)
                                  'arguments (for/list ([a (in-list (prompt-descriptor-arguments d))])
                                               (hasheq 'name (symbol->string (argument-name a)) 'required (not (argument-optional? a)))))))]
))
