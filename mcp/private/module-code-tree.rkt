#lang racket/base
(provide module-code-tree module-code-identity)
;; The compiled-file loader can retain the parent declaration name while
;; evaluating a separately stored submodule. Its compiled name carries the
;; complete submodule suffix; use that suffix without changing the file/symbol.
(define (module-code-identity identity code)
  (define compiled-name (module-compiled-name code))
  (define name (resolved-module-path-name identity))
  (if (pair? compiled-name)
      (make-resolved-module-path
        (cons (if (pair? name) (car name) name) (cdr compiled-name)))
      identity))
;; Nested module declarations travel inside their parent's compiled object and
;; need not receive separate calls to current-eval. Retain those exact objects,
;; including module* declarations, under their resolved declaration identities.
(define (module-code-tree identity code)
  (define actual (module-code-identity identity code))
  (define name (resolved-module-path-name actual))
  (define parent (if (pair? name) name (list name)))
  (cons (cons actual code)
    (append-map-children
      parent (append (module-compiled-submodules code #t)
                     (module-compiled-submodules code #f)))))
(define (append-map-children parent children)
  (if (null? children)
      '()
      (let* ([child (car children)]
             [names (module-compiled-name child)]
             [leaf (if (pair? names) (car (reverse names)) names)]
             [identity (make-resolved-module-path (append parent (list leaf)))])
        (append (module-code-tree identity child)
                (append-map-children parent (cdr children))))))
