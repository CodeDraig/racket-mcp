#lang racket/base
(require mcp (for-syntax racket/base syntax/parse mcp/extension))
(define-syntax checked-effect
 (syntax-parser
  [(_ adapter:id)
   (require-mcp-binding #'adapter '(effect) #:space 'effect #:context this-syntax)
   #'"known"]))
(workflow (effect-query) #:version "1"
 (perform [saved Any] #:adapter writer #:policy idempotent "value")
 (text-result (checked-effect writer)))
