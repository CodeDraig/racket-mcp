#lang racket/base
(require racket/list "descriptor.rkt" "effect.rkt" "completion.rkt" "uri-template.rkt" "private/registration.rkt" "private/adapter-policy.rkt" (only-in "authorization.rkt" check-scopes!) (for-syntax racket/base syntax/parse))
(provide mount mount-interfaces view role message image-content audio-content)
(define-syntax (mount stx) (syntax-parse stx [(_ interface:expr ...)
                                           #`(let ([result (mount-interfaces interface ...)])
                                               (register-declaration result #:mount (interface ...) #,stx view mount-interfaces
                                                                     #,(eq? (syntax-local-context) 'module))
                                               result)]))
(define (mount-interfaces . interfaces)
  (make-interface #:tools (append-map interface-descriptor-tools interfaces)
                  #:resources (append-map interface-descriptor-resources interfaces)
                  #:prompts (append-map interface-descriptor-prompts interfaces)
                  #:completions (append-map interface-descriptor-completions interfaces)
                  #:references
                  (for*/fold ([references (hasheq)]) ([interface (in-list interfaces)]
                    [(source targets) (in-hash (interface-resource-references interface))])
                    (hash-set references source (append (hash-ref references source '()) targets)))
                  #:adapter-bindings
                  (for*/hasheq ([interface (in-list interfaces)] [(target bindings) (in-hash (interface-adapter-bindings interface))])
                    (values target bindings))
                  #:adapter-restrictions
                  (for*/fold ([restrictions (hasheq)]) ([interface (in-list interfaces)]
                    [(target allowed) (in-hash (interface-adapter-restrictions interface))])
                    (hash-set restrictions target
                      (intersect-allowed-adapters (hash-ref restrictions target #f) allowed)))
                  #:requirements
                  (for*/fold ([requirements (hasheq)]) ([interface (in-list interfaces)]
                    [(target scopes) (in-hash (interface-requirements interface))])
                    (hash-set requirements target (remove-duplicates
                      (append (hash-ref requirements target '()) scopes))))))
(define (view iface #:include [include #f] #:exclude [exclude '()] #:rename [rename (hash)] #:namespace [namespace ""] #:uris [uris (hash)] #:require-scopes [scopes '()] #:adapters [adapters (hasheq)] #:allow-adapters [allowed #f])
  (define replacements (check-adapter-bindings adapters))
  (define permitted (check-allowed-adapters allowed))
  (check-scopes! scopes)
  (define (keep? name) (and (or (not include) (member name include)) (not (member name exclude))))
  (define (name old) (string-append namespace (hash-ref rename old old)))
  (define targets (make-hasheq))
  (define resources
    (for/list ([d (in-list (interface-descriptor-resources iface))] #:when (keep? (resource-descriptor-name d)))
      (define old-uri (resource-descriptor-uri d))
      (define uri (hash-ref uris old-uri old-uri))
      (unless (equal? (sort (uri-template-variables old-uri) symbol<?)
                      (sort (uri-template-variables uri) symbol<?))
        (error 'view "URI remapping must preserve template variables"))
      (define transformed
        (struct-copy resource-descriptor d [name (name (resource-descriptor-name d))] [uri uri]
                     [matcher (if (equal? uri old-uri) (resource-descriptor-matcher d) (uri-template-matcher uri))]))
      (hash-set! targets d transformed)
      transformed))
  (define prompts
    (for/list ([d (in-list (interface-descriptor-prompts iface))] #:when (keep? (prompt-descriptor-name d)))
      (define transformed (struct-copy prompt-descriptor d [name (name (prompt-descriptor-name d))]))
      (hash-set! targets d transformed)
      transformed))
  (define tools
    (for/list ([d (in-list (interface-descriptor-tools iface))] #:when (keep? (tool-descriptor-name d)))
      (define transformed (struct-copy tool-descriptor d [name (name (tool-descriptor-name d))]))
      (hash-set! targets d transformed)
      transformed))
  (make-interface #:server (interface-descriptor-server iface)
    #:tools tools
    #:references (for/hasheq ([(original transformed) (in-hash targets)]
                              #:when (hash-has-key? (interface-resource-references iface) original))
                   (values transformed (hash-ref (interface-resource-references iface) original)))
    #:adapter-bindings (for/hasheq ([(original transformed) (in-hash targets)])
      (values transformed
        (for/fold ([bindings (hash-ref (interface-adapter-bindings iface) original (hasheq))])
                  ([(name adapter) (in-hash replacements)]) (hash-set bindings name adapter))))
    #:adapter-restrictions (for/hasheq ([(original transformed) (in-hash targets)])
      (values transformed (intersect-allowed-adapters
                            (hash-ref (interface-adapter-restrictions iface) original #f) permitted)))
    #:requirements (for/hasheq ([(original transformed) (in-hash targets)])
      (values transformed (remove-duplicates
        (append (hash-ref (interface-requirements iface) original '()) scopes))))
    #:resources resources
    #:completions (for/list ([d (in-list (interface-descriptor-completions iface))]
                            #:when (hash-has-key? targets (completion-descriptor-target d)))
                    (struct-copy completion-descriptor d [target (hash-ref targets (completion-descriptor-target d))]))
    #:prompts prompts))
(define (message role content) (hasheq 'role role 'content content))
(define (role who . contents) (map (lambda (content) (message who content)) contents))
(define (image-content data mime) (hasheq 'type "image" 'data data 'mimeType mime))
(define (audio-content data mime) (hasheq 'type "audio" 'data data 'mimeType mime))
