#lang racket/base
(provide resolve-module-import resolved-module-imports)
;; Reflected import indices can have an unspecified base. Resolve a fresh index
;; chain against the declaring module, never against the loader's directory and
;; never by mutating the resolution cache in the reflected index itself.
(define (resolve-module-import owner index)
  (define (rebase index)
    (define-values (path base) (module-path-index-split index))
    (if path
        (module-path-index-join path
          (cond [(module-path-index? base) (rebase base)]
                [base base]
                [else owner]))
        owner))
  (define rebased (rebase index))
  (if (resolved-module-path? rebased) rebased (module-path-index-resolve rebased)))
(define (resolved-module-imports owner)
  (for*/list ([phase-imports (in-list (module->imports owner))]
              [dependency (in-list (cdr phase-imports))])
    (resolve-module-import owner dependency)))
