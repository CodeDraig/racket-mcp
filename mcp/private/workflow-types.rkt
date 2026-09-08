#lang racket/base
(require racket/list "adapter-policy.rkt" "handler-info.rkt")
(provide (struct-out workflow-stage) (struct-out workflow-descriptor))
;; Shared representation lets descriptor construction check workflow values
;; without loading the execution engine or creating a dependency cycle.
(struct workflow-stage (id kind schema procedure adapter policy) #:transparent)
(struct workflow-descriptor (name version fingerprint stages key changes)
  #:transparent
  #:property prop:declared-adapters
  (lambda (workflow)
    (sort (remove-duplicates
      (for/list ([stage (in-list (workflow-descriptor-stages workflow))]
                 #:when (eq? (workflow-stage-kind stage) 'effect))
        (workflow-stage-adapter stage))) symbol<?))
  #:property prop:resource-references
  (lambda (workflow)
    (append-map (lambda (stage) (handler-resource-references (workflow-stage-procedure stage)))
                (workflow-descriptor-stages workflow))))
