#lang racket/base
(provide (struct-out referenced-handler) (struct-out stateful-handler) (struct-out task-handler) (struct-out bound-task-handler)
         handler-resource-references handler-requires-state? prop:resource-references)
;; A lexical thunk resolves declaration bindings only after module definitions.
;; It never executes the application handler to discover dependencies.
(struct referenced-handler (procedure references)
  #:property prop:procedure (struct-field-index procedure))
;; Descriptor metadata travels with the procedure through copies and views.
;; Merely inspecting this wrapper never invokes application code.
(struct stateful-handler (procedure)
  #:property prop:procedure (struct-field-index procedure))
(struct task-handler stateful-handler (matches? dispatch))
;; Binding validation is local and receives the store, task ID, and reader.
;; Keep the base constructor unchanged for handlers without upstream bindings.
(struct bound-task-handler task-handler (check-binding))
(define (handler-requires-state? handler)
  (or (stateful-handler? handler)
      (and (referenced-handler? handler)
           (handler-requires-state? (referenced-handler-procedure handler)))))
(define-values (prop:resource-references resource-reference-source? resource-reference-source-ref)
  (make-struct-type-property 'mcp-resource-references))
(define (handler-resource-references handler)
  (cond [(referenced-handler? handler) ((referenced-handler-references handler))]
        [(stateful-handler? handler) (handler-resource-references (stateful-handler-procedure handler))]
        [(resource-reference-source? handler) ((resource-reference-source-ref handler) handler)]
        [else '()]))
