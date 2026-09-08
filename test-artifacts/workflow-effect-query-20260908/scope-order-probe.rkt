#lang racket/base
(require mcp/private/domain-bindings
         (for-syntax racket/base syntax/parse mcp/extension))
(define-syntax check (syntax-parser [(_ name:id)
 (displayln (list 'found (and (lookup-mcp-binding #'name #:space 'effect) #t) (lookup-mcp-binding #'name)))
 #'(void)]))
(workflow-effects ([writer 'writer])
 (workflow-environment ([writer "value"]) (check writer)))
(workflow-environment ([writer "value"])
 (workflow-effects ([writer 'writer]) (check writer)))
(workflow-effects ([writer 'writer])
 (let ([writer "value"]) (check writer)))
