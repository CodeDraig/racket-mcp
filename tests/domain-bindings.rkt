#lang racket/base
(require rackunit racket/runtime-path mcp
         (rename-in "binding-provider.rkt" [Label ImportedLabel] [operation imported-operation] [document imported-document])
         "../mcp/private/domain-bindings.rkt")
(check-true (valid? ImportedLabel "label"))
(check-equal? (schema-reference ImportedLabel) ImportedLabel)
(check-equal? (operation-reference imported-operation) imported-operation)
(check-equal? (resource-uri (imported-document "id")) "document:///id")
(check-exn exn:fail:syntax? (lambda () (expand #'(schema-reference imported-operation))))
(check-exn exn:fail:syntax? (lambda () (expand #'(operation-reference ImportedLabel))))
(check-exn #rx"expected a schema" (lambda () (expand #'(tool (bad [x imported-operation]) (text-result "bad")))))
(check-exn #rx"expected a schema" (lambda () (expand #'(tool (bad [x imported-document]) (text-result "bad")))))
(check-exn #rx"expected a schema" (lambda () (expand #'(schema Bad imported-operation))))
;; Host-built schemas stay valid and cannot acquire a declaration class merely
;; by sharing the spelling of a name from another module.
(define dynamic-schema (hasheq 'type "integer"))
(tool (dynamic [n dynamic-schema]) (text-result (number->string n)))
(check-equal? ((tool-descriptor-handler dynamic) (bind-arguments (tool-descriptor-arguments dynamic) (hasheq 'n 2))) (text-result "2"))
(check-equal? (let ([ImportedLabel Integer]) (valid? ImportedLabel 1)) #t)
(define-runtime-path provider "binding-provider.rkt")
(check-equal? (dynamic-require provider 'Label) ImportedLabel)
(check-equal? (tool-descriptor-name (dynamic-require provider 'operation)) "operation")
(check-exn exn:fail:syntax? (lambda () (expand #'(set! ImportedLabel Any))))
;; Workflow stage environments retain lexical mutation within a host stage.
(check-equal? (workflow-environment ([value 1]) (begin (set! value 2) value)) 2)
(check-equal? (let ([adapter "host"])
                (workflow-effects ([adapter 'wire]) (list adapter (effect-reference adapter))))
              '("host" wire))
(check-exn exn:fail:syntax? (lambda () (expand #'(effect-reference imported-operation))))
(check-exn #rx"conflicting policies"
           (lambda ()
             (expand #'(workflow (bad-policies) #:version "1"
                         (perform [first Integer] #:adapter writer #:policy manual 1)
                         (perform [second Integer] #:adapter writer #:policy idempotent 2)
                         (text-result "bad")))))

(check-exn #rx"conflicting policies"
           (lambda ()
             (make-workflow "bad" "1" "1"
               (list (workflow-stage 'first 'effect Integer values 'writer 'manual)
                     (workflow-stage 'second 'effect Integer values 'writer 'idempotent)))))
(module phase-user racket/base
  (require (for-syntax racket/base mcp "binding-provider.rkt"))
  (provide baked)
  (define-syntax (emit-schema stx) #`'#,Label)
  (define baked (emit-schema)))
(require (submod "." phase-user))
(check-equal? baked ImportedLabel)
