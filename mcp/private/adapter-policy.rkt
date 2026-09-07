#lang racket/base
(require racket/list "../error.rkt")
(provide check-allowed-adapters intersect-allowed-adapters restrict-adapters
         prop:declared-adapters declared-adapters)
(define-values (prop:declared-adapters declared-adapter-source? declared-adapter-source-ref)
  (make-struct-type-property 'mcp-declared-adapters))
(define (declared-adapters value)
  (if (declared-adapter-source? value) ((declared-adapter-source-ref value) value) '()))
(define-values (prop:allowed-adapters restricted-adapters? allowed-adapters-ref)
  (make-impersonator-property 'mcp-allowed-adapters))
(define (check-allowed-adapters allowed)
  (unless (or (not allowed) (and (list? allowed) (andmap symbol? allowed)))
    (raise-argument-error 'adapter-restrictions "#f or list of adapter symbols" allowed))
  (and allowed (sort (remove-duplicates allowed) symbol<?)))
(define (intersect-allowed-adapters first second)
  (cond [(not first) second] [(not second) first]
        [else (filter (lambda (name) (memq name second)) first)]))
(define (restrict-adapters bindings allowed #:parent [parent (hasheq)])
  (define inherited (and (restricted-adapters? parent) (allowed-adapters-ref parent)))
  (define combined (intersect-allowed-adapters (check-allowed-adapters allowed) inherited))
  (cond
    [(not combined) bindings]
    [else
     (define (check! name)
       (unless (memq name combined)
         (mcp-error -32001 (format "Effect adapter ~a is not permitted by this interface view" name))))
     ;; Filtering supports ordinary iteration; guarding lookup also rejects a
     ;; forbidden name absent from the configured map. Workflow fingerprint
     ;; construction performs these lookups before checkpoints or task creation.
     (define visible
       (for/hasheq ([(name adapter) (in-hash bindings)] #:when (memq name combined))
         (values name adapter)))
     (chaperone-hash visible
       (lambda (_ name) (check! name) (values name (lambda (_ _name value) value)))
       (lambda (_ name value) (check! name) (values name value))
       (lambda (_ name) name)
       (lambda (_ name) name)
       #f #f prop:allowed-adapters combined)]))
