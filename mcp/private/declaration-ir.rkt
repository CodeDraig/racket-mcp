#lang racket/base
(require racket/list syntax/parse "../uri-template.rkt" "resource-binding.rkt" "prompt-binding.rkt"
         (for-template racket/base "../schema.rkt"))
(provide (struct-out declaration-node) parse-declaration declarations->manifest)
;; This IR contains lexical identifiers and complete source syntax. Only the
;; final manifest conversion discards syntax objects; handlers are never expanded
;; or evaluated here to infer metadata.
(struct declaration-node (kind name source arguments clauses value) #:transparent)
(define (parse-declaration kind name source)
  (define parts (syntax->list source))
  (define signature (and (pair? (cdr parts)) (syntax->list (cadr parts))))
  (define arguments (if (and signature (memq kind '(tool workflow resource prompt))) (cdr signature) '()))
  (define clauses
    (let loop ([rest (if (memq kind '(server)) (cdr parts) (cddr parts))] [out (hasheq)])
      (if (and (pair? rest) (keyword? (syntax-e (car rest))) (pair? (cdr rest)))
          (loop (cddr rest) (hash-set out (syntax-e (car rest)) (cadr rest))) out)))
  (declaration-node kind name source arguments clauses
                    (case kind [(schema) (caddr parts)] [(shape) (cddr parts)]
                      [(completion) (cadr signature)] [else #f])))
(define unknown (gensym 'unknown))
(define (literal stx)
  (define datum (syntax->datum stx))
  (cond [(or (string? datum) (boolean? datum) (number? datum) (hash? datum)) datum]
        [else (syntax-parse stx #:literals (quote)
                [(quote value) (syntax->datum #'value)] [_ unknown])]))
(define (source-fields stx)
  (hasheq 'source (format "~a" (syntax-source stx)) 'line (syntax-line stx)
          'column (syntax-column stx) 'position (syntax-position stx) 'span (syntax-span stx)))
(define (declarations->manifest nodes)
  (define (schema-value stx [seen '()])
    (define basic
      (for/or ([id (in-list (list #'String #'Integer #'Number #'Boolean #'Null #'Any))]
               [value (in-list (list (hasheq 'type "string") (hasheq 'type "integer") (hasheq 'type "number") (hasheq 'type "boolean") (hasheq 'type "null") #t))])
        (and (identifier? stx) (free-identifier=? id stx) (cons #t value))))
    (cond [basic (cdr basic)]
          [(identifier? stx)
           (define node (findf (lambda (node) (and (memq (declaration-node-kind node) '(schema shape))
                                                 (free-identifier=? stx (declaration-node-name node)))) nodes))
           (cond [(not node) unknown]
                 [(memq node seen) (raise-syntax-error 'schema "cyclic schema alias" (declaration-node-source node) stx)]
                 [(eq? (declaration-node-kind node) 'schema) (schema-value (declaration-node-value node) (cons node seen))]
                 [else
                  (define fields (map syntax->list (declaration-node-value node)))
                  (define field-schemas (map (lambda (field) (schema-value (cadr field) (cons node seen))) fields))
                  (if (memq unknown field-schemas) unknown
                      (hasheq 'type "object" 'additionalProperties #f
                              'required (map (lambda (field) (symbol->string (syntax-e (car field)))) fields)
                              'properties (for/hasheq ([field (in-list fields)] [value (in-list field-schemas)])
                                            (values (syntax-e (car field)) value))))])]
          [else (literal stx)]))
  (define (describe stx [schema? #f])
    (define value ((if schema? schema-value literal) stx))
    (if (eq? value unknown)
        (hasheq 'known? #f 'expression (format "~s" (syntax->datum stx)))
        (hasheq 'known? #t 'value value)))
  (define seen (make-hash))
  (define (completion-target node)
    (findf (lambda (candidate)
             (and (memq (declaration-node-kind candidate) '(schema shape tool workflow resource prompt))
                  (identifier? (declaration-node-name candidate))
                  (free-identifier=? (declaration-node-name node) (declaration-node-name candidate)))) nodes))
  (define (imported-target node)
    (define id (declaration-node-name node))
    (define resource (lookup-resource-binding id))
    (define prompt (and (not resource) (lookup-prompt-binding id)))
    (cond [resource (hasheq 'kind 'resource 'name (resource-binding-name resource) 'arguments (resource-binding-arguments resource))]
          [prompt (hasheq 'kind 'prompt 'name (prompt-binding-name prompt) 'arguments (prompt-binding-arguments prompt))]
          [else #f]))
  (define completion-bindings '())
  (for ([node (in-list nodes)])
    (define kind (declaration-node-kind node))
    (when (eq? kind 'completion)
      (define target (completion-target node))
      (define imported (and (not target) (imported-target node)))
      (when (and imported (not (memq (syntax-e (declaration-node-value node)) (hash-ref imported 'arguments))))
        (raise-syntax-error 'completion "unknown target argument" (declaration-node-source node) (declaration-node-value node)))
      (when (or target imported)
        (for ([previous (in-list completion-bindings)])
          (when (and (free-identifier=? (declaration-node-name node) (declaration-node-name previous))
                     (eq? (syntax-e (declaration-node-value node)) (syntax-e (declaration-node-value previous))))
            (raise-syntax-error 'mcp "duplicate statically known published identity" (declaration-node-source node) (declaration-node-name node))))
        (set! completion-bindings (cons node completion-bindings)))
      (when target
        (unless (memq (declaration-node-kind target) '(resource prompt))
          (raise-syntax-error 'completion "target must be a resource or prompt" (declaration-node-source node) (declaration-node-name node)))
        (unless (for/or ([argument (in-list (declaration-node-arguments target))])
                  (eq? (syntax-e (car (syntax->list argument))) (syntax-e (declaration-node-value node))))
          (raise-syntax-error 'completion "unknown target argument" (declaration-node-source node) (declaration-node-value node)))))
    (define key (case kind
                  [(tool workflow) (cons 'tool (syntax-e (declaration-node-name node)))]
                  [(prompt) (cons 'prompt (syntax-e (declaration-node-name node)))]
                  [(server) '(server)]
                  [(completion)
                   (define target (completion-target node))
                   (and target (list 'completion target (syntax-e (declaration-node-value node))))]
                  [(resource) (define uri (hash-ref (declaration-node-clauses node) '#:uri #f))
                              (and uri (let ([value (literal uri)]) (and (not (eq? value unknown)) (cons 'resource-uri value))))]
                  [else #f]))
    (when key
      (when (hash-has-key? seen key)
        (raise-syntax-error 'mcp "duplicate statically known published identity" (declaration-node-source node) (declaration-node-name node)))
      (hash-set! seen key #t)))
  (define resource-routes '())
  (for ([node (in-list nodes)] #:when (eq? (declaration-node-kind node) 'resource))
    (define clauses (declaration-node-clauses node))
    (define uri-source (hash-ref clauses '#:uri #f))
    (define uri (and uri-source (literal uri-source)))
    (define matcher-source (hash-ref clauses '#:matcher #f))
    (when (and (string? uri) (or (not matcher-source) (eq? (literal matcher-source) #f)))
      (define matcher
        (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'resource (exn-message e) uri-source))])
          (uri-template-matcher uri)))
      (for ([previous (in-list resource-routes)])
        (define witness
          (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'resource (exn-message e) uri-source))])
            (uri-matchers-overlap matcher (cdr previous))))
        (when (string? witness)
          (raise-syntax-error 'resource
            (format "overlapping resource URI routes ~a and ~a; both match ~s" uri (car previous) witness) uri-source)))
      (set! resource-routes (cons (cons uri matcher) resource-routes))))
  (for/list ([node (in-list nodes)])
    (define kind (declaration-node-kind node))
    (define metadata
      (for/hasheq ([(keyword expression) (in-hash (declaration-node-clauses node))])
        (values (string->symbol (keyword->string keyword))
                (cond [(and (eq? kind 'workflow) (eq? keyword '#:execution))
                       ;; This is a checked grammar identifier, not a host expression.
                       (hasheq 'known? #t 'value (syntax-e expression))]
                      [(and (eq? kind 'server) (eq? keyword '#:instructions)
                            (eq? (literal expression) #f))
                       (hasheq 'known? #t 'value "")]
                      [else (describe expression (eq? keyword '#:output))]))))
    (define arguments
      (for/list ([argument (in-list (declaration-node-arguments node))])
        (define parts (syntax->list argument))
        (define options (cddr parts))
        (define optional? (for/or ([part (in-list options)]) (memq (syntax-e part) '(#:optional #:default))))
        (define extra
          (let loop ([parts options] [out (hasheq)])
            (cond [(null? parts) out]
                  [(eq? (syntax-e (car parts)) '#:optional) (loop (cdr parts) out)]
                  [else (loop (cddr parts) (hash-set out (string->symbol (keyword->string (syntax-e (car parts)))) (describe (cadr parts))))])))
        (hash-set* extra 'name (syntax-e (car parts)) 'required (not optional?) 'schema (describe (cadr parts) #t))))
    (define result
      (hash-set* (source-fields (declaration-node-source node)) 'kind kind 'name (syntax->datum (declaration-node-name node))
                 'arguments arguments 'metadata metadata 'manifest-version 2))
    (define with-schema
      (cond [(eq? kind 'completion)
             (define target (completion-target node))
             (define imported (and (not target) (imported-target node)))
             (hash-set* result 'argument (syntax-e (declaration-node-value node))
                        'target (cond [target
                                      (hasheq 'known? #t 'kind (declaration-node-kind target)
                                              'name (syntax-e (declaration-node-name target)))]
                                     [imported (hasheq 'known? #t 'kind (hash-ref imported 'kind) 'name (hash-ref imported 'name))]
                                     [else (hasheq 'known? #f 'expression (format "~s" (syntax->datum (declaration-node-name node))))]))]
            [(memq kind '(schema shape)) (hash-set result 'schema (describe (declaration-node-name node) #t))]
            [(memq kind '(tool workflow))
             (hash-set result 'input-schema
                       (if (andmap (lambda (argument) (hash-ref (hash-ref argument 'schema) 'known?)) arguments)
                           (hasheq 'known? #t 'value
                                   (hasheq 'type "object" 'additionalProperties #f
                                           'required (for/list ([a (in-list arguments)] #:when (hash-ref a 'required)) (symbol->string (hash-ref a 'name)))
                                           'properties (for/hasheq ([a (in-list arguments)]) (values (hash-ref a 'name) (hash-ref (hash-ref a 'schema) 'value)))))
                           (hasheq 'known? #f 'expression "dynamic argument schemas")))]
            [else result]))
    (define with-workflow
      (if (and (memq kind '(workflow resource prompt)) (declaration-node-value node))
          (let* ([stages (declaration-node-value node)]
                 [kinds (map (lambda (stage) (syntax-e (cadr (syntax->list stage)))) stages)]
                 [execution-source (hash-ref (declaration-node-clauses node) '#:execution #f)]
                 [execution (if execution-source (syntax-e execution-source) 'mrtr)]
                 [task-capability (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))]
                 [required (if (eq? execution 'task) task-capability (hasheq))])
          (hash-set* with-schema
                     'runtime-requirements
                     (append '(workflow-storage)
                             (if (memq 'effect kinds) '(adapters) '())
                             (if (memq execution '(task task-optional)) '(task-workers) '()))
                     'client-capabilities
                     (hasheq 'required (if (ormap (lambda (kind) (memq kind '(input input-group))) kinds)
                                          (hash-set required 'elicitation (hasheq)) required)
                             'optional (if (eq? execution 'task-optional) task-capability (hasheq))
                             'analysis 'declared-workflow-stages)
                     'workflow-stages
                     (for/list ([stage (in-list (declaration-node-value node))])
                       (define fields (syntax->list stage))
                       (hash-set* (source-fields (list-ref fields 5))
                                  'id (syntax-e (car fields)) 'kind (syntax-e (cadr fields))
                                  'schema (describe (caddr fields) #t)
                                  'adapter-or-targets (syntax->datum (list-ref fields 3))
                                  'policy (syntax->datum (list-ref fields 4))))))
          with-schema))
    (define dynamic?
      (let walk ([value with-workflow])
        (cond [(hash? value) (or (eq? (hash-ref value 'known? #t) #f) (for/or ([child (in-hash-values value)]) (walk child)))]
              [(list? value) (ormap walk value)] [else #f])))
    (hash-set with-workflow 'dynamic-metadata dynamic?)))
