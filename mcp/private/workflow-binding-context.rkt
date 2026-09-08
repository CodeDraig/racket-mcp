#lang racket/base
(provide call-with-workflow-binding-context workflow-context-binding?)

;; During stage expansion the compiler has parsed the lexical environment but
;; has not emitted its syntax-spec workflow-environment form yet. Expose only
;; that environment to binding queries, for the dynamic extent of one expansion.
;; Identifiers retain scopes; no spelling-based or global registration is used.
(define current-bindings (make-parameter '()))
;; The caller and a nested extension see different current introduction scopes.
;; Flip only that scope, then remove use-site scopes as for a binding position.
;; Other introduction and lexical scopes must survive the comparison.
(define (binding-id id) (syntax-local-identifier-as-binding (syntax-local-introduce id)))
(define (call-with-workflow-binding-context ids thunk)
  (parameterize ([current-bindings (map binding-id ids)]) (thunk)))
(define (workflow-context-binding? id)
  (for/or ([bound (in-list (current-bindings))])
    (bound-identifier=? (binding-id id) bound)))
