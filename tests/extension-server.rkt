#lang mcp
(require (for-syntax racket/base syntax/parse))
(define-mcp-extension declare-server #:declaration
  (syntax-parser [(_) #'(server #:name "extension-server" #:version "1")]))
(declare-server)
(tool (ping) (text-result "pong"))
