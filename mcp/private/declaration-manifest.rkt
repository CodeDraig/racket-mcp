#lang racket/base
(require "declaration-ir.rkt"
         "declaration-description.rkt"
         "declaration-target.rkt"
         "declaration-check.rkt")
(provide declarations->manifest)
(define (declarations->manifest nodes)
  (define describe (make-declaration-description nodes))
  (check-declarations! nodes)
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
             (define target (completion-target nodes node))
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
