#lang racket/base
(require syntax-spec-v3 "domain-bindings.rkt" "handler-info.rkt"
         (for-syntax racket/base syntax/parse))
(provide mcp-handler mcp-bound-handler)
;; Analyze the complete lambda so host arguments and internal definitions retain
;; their lexical scope. Reference discovery never invokes the procedure.
(syntax-spec
 (host-interface/expression
  (mcp-handler (argument:racket-var ...) body:racket-body ...+)
  #:binding (scope (bind argument) ... (import body) ...)
  (define/syntax-parse (reference ...)
    (resource-referenced-identifiers #'(lambda (argument ...) body ...)))
  #'(referenced-handler (lambda (argument ...) body ...)
                        (lambda () (list reference ...)))))
(define-syntax (mcp-bound-handler stx)
  (syntax-parse stx
    [(_ (argument:id ...) body ...+)
     #'(let ([handler (mcp-handler (argument ...) body ...)])
         (referenced-handler
          (lambda (bound) (handler (hash-ref bound 'argument) ...))
          (referenced-handler-references handler)))]))
