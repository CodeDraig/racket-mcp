#lang racket/base
(require racket/list "declaration-ir.rkt" "resource-binding.rkt" "interface-manifest.rkt" (for-template racket/base))
(provide make-module-compilers)
;; Preserve the defining module, not an import alias or generated binding name.
;; Resolving an already expanded binding does not instantiate its provider.
(define (reference-provider target)
  (define binding (identifier-binding target))
  (and (list? binding)
       (let* ([name (resolved-module-path-name (module-path-index-resolve (car binding)))]
              [root (if (pair? name) (car name) name)])
         (hasheq 'kind (if (path? root) "file" "symbol")
                 'module (if (path? root) (path->string root) (symbol->string root))
                 'submodules (if (pair? name) (map symbol->string (cdr name)) '())
                 'phase (list-ref binding 4)))))
(define (reference-binding-name target)
  (define binding (identifier-binding target))
  (and (list? binding) (symbol->string (cadr binding))))
;; Each module owns a lexical collector/finalizer pair. No process-wide table
;; communicates between modules or transformer instances.
(define (make-module-compilers runtime-register interface-runtime)
  (define entries '())
  (define references '())
  (values
   (lambda (stx)
     (syntax-case stx ()
       [(_ descriptor #:mount (expression ...) source view-id mount-id unconditional?)
        (begin (set! entries (cons (mounted-node (syntax->list #'(expression ...)) #'source #'view-id #'mount-id (syntax-e #'unconditional?)) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor #:references owner (target ...))
        (begin (set! references (cons (cons #'owner (syntax->list #'(target ...))) references)) #'(void))]
       [(_ descriptor #:declaration kind name source #:workflow-nodes (stage ...))
        (begin (set! entries (cons (struct-copy declaration-node (parse-declaration (syntax-e #'kind) #'name #'source)
                                              [value (syntax->list #'(stage ...))]) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor #:declaration kind name source)
        (begin (set! entries (cons (parse-declaration (syntax-e #'kind) #'name #'source) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor info)
        (begin (set! entries (cons (cadr (syntax->datum #'info)) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor) #`(#,runtime-register descriptor)]))
   (lambda (stx)
     (define ordered (reverse entries))
     (define nodes (filter declaration-node? ordered))
     (define local-resources
       (for/list ([node (in-list nodes)] [index (in-naturals)]
                  #:when (eq? (declaration-node-kind node) 'resource))
         (define binding (lookup-resource-binding (declaration-node-name node)))
         (cons (and binding (local-expand (resource-binding-target binding) 'expression '())) (format "declaration-~a" index))))
     (define compiled
       (for/list ([node (in-list nodes)] [base-entry (in-list (declarations->manifest nodes))]
                  [index (in-naturals)])
         (define entry
           (if (eq? (declaration-node-kind node) 'resource)
               (let ([target (car (findf (lambda (pair) (equal? (cdr pair) (format "declaration-~a" index))) local-resources))])
                 (hash-set* base-entry 'local-id (format "declaration-~a" index)
                            'binding-origin (and target
                              (hash-set* (or (syntax-property (resource-binding-target (lookup-resource-binding (declaration-node-name node))) 'mcp-resource-origin) (hasheq 'name #f 'known? #f))
                                         'binding-provider (reference-provider target)
                                         'binding-name (reference-binding-name target))))) base-entry))
         (define targets
           (append-map cdr (filter (lambda (group) (and (identifier? (declaration-node-name node)) (free-identifier=? (car group) (declaration-node-name node)))) references)))
         (define origins
           (remove-duplicates
            (for/list ([target (in-list targets)])
              (hash-set*
                (or (syntax-property target 'mcp-resource-origin) (hasheq 'name #f 'known? #f))
                'binding-provider (reference-provider target)
                'binding-name (reference-binding-name target)
                'local-target
                (for/first ([resource (in-list local-resources)]
                            #:when (and (car resource) (free-identifier=? target (car resource))))
                  (cdr resource)))) equal?))
         (if (memq (declaration-node-kind node) '(tool resource prompt workflow))
             (hash-set* entry 'resource-references (sort origins string<? #:key (lambda (origin) (format "~a:~a:~a" (hash-ref origin 'source "") (hash-ref origin 'position 0) (hash-ref origin 'name))))
                        'reference-analysis 'lexical-handler-syntax) entry)))
     ;; Called in the final generated RHS, after application RHS expansion.
     ;; Lift a fresh, independent module containing only quoted manifest data.
     (define exclusions '())
     (define (record-exclusion entry) (set! exclusions (cons entry exclusions)))
     (define combined
       (append compiled
               (append-map (lambda (entry index)
                             (cond [(mounted-node? entry) (mount-manifest entry index #:record-exclusion record-exclusion)]
                                   [(declaration-node? entry) '()]
                                   [else (list entry)])) ordered (range (length ordered)))))
     (when (ormap mounted-node? ordered)
       (check-composed-manifest combined (mounted-node-source (findf mounted-node? ordered))))
     (define manifest (resolve-mounted-references combined #:exclusions exclusions))
     (syntax-local-lift-module
      #`(module manifest racket/base (provide manifest manifest-version manifest-provider manifest-exclusions)
          (define manifest-version 2)
          (define manifest-provider '#,(reference-provider interface-runtime))
          (define manifest-exclusions '#,(remove-duplicates (reverse exclusions) equal?))
          (define manifest '#,manifest)))
     #'(void))))
