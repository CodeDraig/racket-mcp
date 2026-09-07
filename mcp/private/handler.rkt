#lang racket/base
(require racket/stxparam "registration.rkt" syntax-spec-v3 "domain-bindings.rkt" "handler-info.rkt"
         (for-syntax racket/base syntax/parse))
(provide mcp-handler mcp-bound-handler mcp-owned-handler)
(define-syntax-parameter current-handler-owner (lambda (_) #'#f))
(define-syntax-rule (mcp-owned-handler owner (argument ...) body ...)
  (syntax-parameterize ([current-handler-owner (lambda (_) (quote-syntax owner))])
    (mcp-handler (argument ...) body ...)))
;; Analyze the complete lambda so host arguments and internal definitions retain
;; their lexical scope. Reference discovery never invokes the procedure.
(syntax-spec
 (host-interface/expression
  (mcp-handler (argument:racket-var ...) body:racket-body ...+)
  #:binding (scope (bind argument) ... (import body) ...)
  (define/syntax-parse (reference ...)
    (resource-referenced-identifiers #'(lambda (argument ...) body ...)))
  (define owner ((syntax-parameter-value #'current-handler-owner) #'current-handler-owner))
  #`(begin
      #,(if (identifier? owner) #`(register-declaration #f #:references #,owner (reference ...)) #'(void))
      (referenced-handler (lambda (argument ...) body ...)
                          (lambda () (list reference ...))))))
(define-syntax (mcp-bound-handler stx)
  (syntax-parse stx
    [(_ owner:id (argument:id ...) body ...+)
     #'(let ([handler (mcp-owned-handler owner (argument ...) body ...)])
         (referenced-handler
          (lambda (bound) (handler (hash-ref bound 'argument) ...))
          (referenced-handler-references handler)))]))
