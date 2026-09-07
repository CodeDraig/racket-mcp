#lang racket/base
(require syntax-spec-v3 (for-syntax racket/base syntax/parse))
(provide mcp-handler)
;; The host body retains Racket binding and definition semantics. This private
;; boundary is also used by generated handlers, never by descriptor clients.
(syntax-spec
 (host-interface/expression
  (mcp-handler (argument:racket-var ...) body:racket-body ...+)
  #:binding (scope (bind argument) ... (import body) ...)
  #'(lambda (argument ...) body ...)))
