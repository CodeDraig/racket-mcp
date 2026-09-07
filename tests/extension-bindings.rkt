#lang racket/base
(require rackunit mcp mcp/extension
         "../mcp/private/domain-bindings.rkt"
         "../examples/extensions/resource-link-tool.rkt"
         (rename-in "binding-provider.rkt" [Label ImportedLabel] [operation imported-operation] [document imported-document])
         (for-syntax racket/base syntax/parse mcp/extension))
(define-syntax (describe stx)
  (syntax-parse stx
    [(_ name:id (~optional space:id #:defaults ([space #'value])))
     (define info (lookup-mcp-binding #'name #:space (syntax-e #'space)))
     #`'#,(and info (list (mcp-binding-info-kind info) (mcp-binding-info-name info) (mcp-binding-info-arguments info)))]))
(schema Label String)
(tool (operation) (text-result "operation"))
(resource (document [id String]) #:uri "extension:///{id}" id)
(prompt (greeting [name String]) (role "user" (text-content name)))
(check-equal? (describe Label) '(schema #f #f))
(check-equal? (describe ImportedLabel) '(schema #f #f))
(check-equal? (describe operation) '(operation #f #f))
(check-equal? (describe imported-operation) '(operation #f #f))
(check-equal? (describe document) '(resource document (id)))
(check-equal? (describe imported-document) '(resource document (id)))
(check-equal? (describe greeting) '(prompt greeting (name)))
(check-false (describe string-append))
(check-false (let ([document 1]) (describe document)))
(check-equal? (workflow-environment ([saved 1]) (describe saved)) '(workflow-value #f #f))
(check-equal? (let ([writer "host"])
                (workflow-effects ([writer 'adapter]) (list (describe writer) (describe writer effect))))
              '(#f (effect #f #f)))
(check-exn #rx"only available during syntax expansion" (lambda () (lookup-mcp-binding #'document)))
(check-exn exn:fail:contract? (lambda () (lookup-mcp-binding #'(not an identifier))))
(check-exn exn:fail:contract? (lambda () (require-mcp-binding #'document '())))
(resource-link-tool open-document (document "a b"))
(define rt (make-runtime (make-interface #:tools (list open-document) #:resources (list document))))
(define result (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "open-document")))
(check-equal? (hash-ref (car (hash-ref result 'content)) 'uri) "extension:///a%20b")
(check-equal? (tool-descriptor-description open-document) "Link to document.")
(check-exn
  (lambda (e) (and (exn:fail:syntax? e) (regexp-match? #rx"expected MCP resource binding" (exn-message e))
                   (for/or ([s (in-list (exn:fail:syntax-exprs e))]) (eq? (syntax-e s) 'greeting))))
  (lambda () (expand #'(resource-link-tool wrong (greeting "name")))))
(check-exn #rx"resource reference expects 1 arguments"
  (lambda () (expand #'(resource-link-tool wrong-arity (document)))))
(custodian-shutdown-all (runtime-custodian rt))

(module shifted racket/base
  (require (for-syntax racket/base mcp "binding-provider.rkt")
           (for-meta 2 racket/base syntax/parse mcp/extension))
  (provide baked)
  (begin-for-syntax
    (schema PhaseLabel String)
    (define-syntax (classify stx)
      (syntax-parse stx
        [(_ name:id) #`'#,(mcp-binding-info-kind (require-mcp-binding #'name '(schema)))]))
    (define kind (list (classify Label) (classify PhaseLabel))))
  (define-syntax (emit stx) #`'#,kind)
  (define baked (emit)))
(require (submod "." shifted))
(check-equal? baked '(schema schema))
