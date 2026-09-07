#lang racket/base
(require syntax-spec-v3 (for-syntax racket/base syntax/parse "resource-binding.rkt" "prompt-binding.rkt"))
(provide define-schema-value define-operation-value define-resource-value
         schema-reference operation-reference resource-reference effect-reference workflow-effects workflow-environment checked-schema-expression)
;; Public declarations retain ordinary Racket values through reference compilers.
;; The classes are private compiler contracts, not runtime descriptor variants.
(syntax-spec
 (binding-class schema-name #:description "MCP schema binding" #:reference-compiler immutable-reference-compiler)
 (binding-class operation-name #:description "MCP operation binding" #:reference-compiler immutable-reference-compiler)
 (binding-class resource-name #:description "MCP resource binding" #:reference-compiler immutable-reference-compiler)
 (binding-class effect-name #:description "MCP effect binding" #:binding-space mcp-effect #:reference-compiler immutable-reference-compiler)
 (binding-class workflow-value #:description "MCP workflow value" #:reference-compiler mutable-reference-compiler)
 (host-interface/definition
  (define-schema-value/core name:schema-name value:racket-expr)
  #:binding (export name)
  #:lhs [#'name]
  #:rhs [#'value])
 (host-interface/definition
  (define-operation-value/core name:operation-name value:racket-expr)
  #:binding (export name)
  #:lhs [#'name]
  #:rhs [#'value])
 (host-interface/definition
  (define-resource-value/core name:resource-name value:racket-expr)
  #:binding (export name)
  #:lhs [#'name]
  #:rhs [#'value])
 (host-interface/expression (schema-reference name:schema-name) #'name)
 (host-interface/expression (operation-reference/core name:operation-name) #'name)
 (host-interface/expression (resource-reference name:resource-name) #'name)
 (host-interface/expression (effect-reference name:effect-name) #'name)
 (host-interface/expression
  (workflow-effects ([name:effect-name value:racket-expr] ...) body:racket-expr)
  #:binding (scope (bind name) ... body)
  #'(let ([name value] ...) body))
 (host-interface/expression
  (workflow-environment ([name:workflow-value value:racket-expr] ...) body:racket-expr)
  #:binding (scope (bind name) ... body)
  #'(let ([name value] ...) body)))

(define-syntax (operation-reference stx)
  (syntax-parse stx
    [(_ name:id)
     (define prompt (lookup-prompt-binding #'name))
     #`(operation-reference/core #,(if prompt (prompt-binding-target prompt) #'name))]))

;; Only inspect known declaration bindings. Ordinary Racket expressions and
;; dynamically constructed schema values retain their normal expansion path.
(define-syntax (checked-schema-expression stx)
  (syntax-parse stx
    [(_ value:id)
     (define resource? (resource-binding? (syntax-local-value #'value (lambda () #f))))
     (define operation?
       (with-handlers ([exn:fail:syntax? (lambda (_) #f)])
         (local-expand #'(operation-reference value) 'expression '())
         #t))
     (when (or resource? operation?)
       (raise-syntax-error #f "expected a schema, received an MCP operation or resource binding" stx #'value))
     #'value]
    [(_ value:expr) #'value]))

(define-syntax (define-schema-value stx)
  (syntax-parse stx
    [(_ name:id value:expr)
     (if (eq? (syntax-local-context) 'top-level)
         #'(define name value)
         #'(define-schema-value/core name value))]))

(define-syntax (define-operation-value stx)
  (syntax-parse stx
    [(_ name:id value:expr)
     (if (eq? (syntax-local-context) 'top-level)
         #'(define name value)
         #'(define-operation-value/core name value))]))

(define-syntax (define-resource-value stx)
  (syntax-parse stx
    [(_ name:id value:expr)
     (if (eq? (syntax-local-context) 'top-level)
         #'(define name value)
         #'(define-resource-value/core name value))]))

(provide (for-syntax lookup-domain-kind))
(begin-for-syntax
  (define (lookup-domain-kind id #:space [space 'value])
    (with-handlers ([exn:fail:syntax? (lambda (_) #f)])
      (define scoped (if (eq? space 'effect) ((make-interned-syntax-introducer 'mcp-effect) id 'add) id))
      (define value (syntax-local-value scoped (lambda () #f)))
      (cond [(eq? space 'effect) (and ((binding-class-predicate effect-name) value) 'effect)]
            [((binding-class-predicate schema-name) value) 'schema]
            [((binding-class-predicate operation-name) value) 'operation]
            [((binding-class-predicate resource-name) value) 'resource]
            [((binding-class-predicate workflow-value) value) 'workflow-value]
            [else #f]))))
