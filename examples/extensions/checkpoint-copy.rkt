#lang racket/base
(require mcp (for-syntax racket/base syntax/parse mcp/extension))
(provide checkpoint-copy)

;; The source must already be a workflow value. Its representation is explicit;
;; the normal checkpoint compiler and runtime still check the emitted stage.
(define-mcp-extension checkpoint-copy #:workflow
  (syntax-parser
    [(_ [target:id representation:expr] source:id)
     (require-mcp-binding #'source '(workflow-value) #:context this-syntax)
     #'(checkpoint [target representation] source)]))
