#lang racket/base
(require mcp (for-syntax racket/base syntax/parse mcp/extension))
(define-mcp-extension checked-effect #:workflow
 (syntax-parser
  [(_ adapter:id)
   (require-mcp-binding #'adapter '(effect) #:space 'effect #:context this-syntax)
   #'(text-result "known")]))
(workflow (effect-query) #:version "1"
 (perform [saved Any] #:adapter writer #:policy idempotent "value")
 (checked-effect writer))
