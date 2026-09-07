#lang racket/base
(require mcp (for-syntax racket/base syntax/parse))
(provide request-approval)
;; A separately compiled workflow extension. The public binder is supplied by
;; the caller; schema and request identifiers retain this module's bindings.
(define-mcp-extension request-approval #:workflow
  (syntax-parser
    [(_ response:id message-expression:expr)
     #'(await-input [response Any]
         (hasheq 'mode "form" 'message message-expression
                 'requestedSchema (object-schema (hasheq 'approved Boolean))))]))
