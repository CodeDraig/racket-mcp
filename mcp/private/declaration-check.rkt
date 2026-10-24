#lang racket/base
(require "declaration-ir.rkt"
         "declaration-description.rkt"
         "declaration-target.rkt"
         "../uri-template.rkt")
(provide check-declarations!)
(define (check-declarations! nodes)
  (define seen (make-hash))
  (define completion-bindings '())
  (for ([node (in-list nodes)])
    (define kind (declaration-node-kind node))
    (when (eq? kind 'completion)
      (define target (completion-target nodes node))
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
                   (define target (completion-target nodes node))
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
)
