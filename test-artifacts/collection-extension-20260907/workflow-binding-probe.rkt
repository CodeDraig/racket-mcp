#lang mcp
(require (for-syntax racket/base syntax/parse mcp/extension))
(define-mcp-extension copy-stage #:workflow
  (syntax-parser
    [(_ target:id source:id)
     (require-mcp-binding #'source '(workflow-value) #:context this-syntax)
     #'(checkpoint [target String] source)]))
(workflow (copy [name String]) #:version "1"
  (copy-stage saved name)
  (text-result saved))
