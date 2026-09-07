#lang racket/base
(require mcp (for-syntax racket/base syntax/parse mcp/extension))
(provide resource-link-tool)
;; Bind a named, zero-argument tool to a resource application. Normal resource
;; reference expansion still checks arity, and mounting resolves its identity.
(define-mcp-extension resource-link-tool
  (syntax-parser
    [(_ name:id (target:id argument:expr ...))
     #:do [(define info (require-mcp-binding #'target '(resource) #:context this-syntax))]
     #:with description (datum->syntax #'name (format "Link to ~a." (mcp-binding-info-name info)) #'name)
     #'(tool (name) #:description description
         (hasheq 'resultType "complete" 'content (list (link (target argument ...)))))]))
