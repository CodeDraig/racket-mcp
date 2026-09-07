#lang racket/base
(provide (struct-out referenced-handler) handler-resource-references prop:resource-references)
;; A lexical thunk resolves declaration bindings only after module definitions.
;; It never executes the application handler to discover dependencies.
(struct referenced-handler (procedure references)
  #:property prop:procedure (struct-field-index procedure))
(define-values (prop:resource-references resource-reference-source? resource-reference-source-ref)
  (make-struct-type-property 'mcp-resource-references))
(define (handler-resource-references handler)
  (cond [(referenced-handler? handler) ((referenced-handler-references handler))]
        [(resource-reference-source? handler) ((resource-reference-source-ref handler) handler)]
        [else '()]))
