#lang racket/base
(require racket/list (for-template racket/base "../workflow.rkt" "domain-bindings.rkt"))
(provide (struct-out workflow-node) check-workflow-nodes emit-workflow-nodes)

;; Source syntax survives lowering so graph errors point at the declaration,
;; rather than at a generated descriptor constructor. This representation is private.
(struct workflow-node (id kind schema procedure adapter policy source) #:transparent)
(define (check-workflow-nodes nodes)
  (define seen (make-hasheq))
  (for ([node (in-list nodes)])
    (when (hash-has-key? seen (workflow-node-id node))
      (raise-syntax-error 'workflow "duplicate persistent stage identity" (workflow-node-source node)))
    (hash-set! seen (workflow-node-id node) #t))
  (for ([node (in-list nodes)])
    (define targets
      (case (workflow-node-kind node)
        [(branch) (workflow-node-adapter node)]
        [(jump) (list (workflow-node-adapter node))]
        [else '()]))
    (for ([target (in-list targets)])
      (unless (hash-has-key? seen target)
        (raise-syntax-error 'workflow "unresolved control-flow destination" (workflow-node-source node)))))
  nodes)
(define (emit-workflow-nodes nodes)
  (for/list ([node (in-list (check-workflow-nodes nodes))])
    #`(workflow-stage '#,(workflow-node-id node) '#,(workflow-node-kind node)
                      (checked-schema-expression #,(workflow-node-schema node)) #,(workflow-node-procedure node)
                      #,(if (eq? (workflow-node-kind node) 'effect) #`(effect-reference #,(workflow-node-adapter node)) #`'#,(workflow-node-adapter node)) '#,(workflow-node-policy node))))
