#lang racket/base
(provide (struct-out referenced-handler) handler-resource-references)
;; A lexical thunk resolves declaration bindings only after module definitions.
;; It never executes the application handler to discover dependencies.
(struct referenced-handler (procedure references)
  #:property prop:procedure (struct-field-index procedure))
(define (handler-resource-references handler)
  (if (referenced-handler? handler) ((referenced-handler-references handler)) '()))
