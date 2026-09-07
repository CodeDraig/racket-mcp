#lang racket/base
(require rackunit (for-syntax racket/base mcp))
(module provider racket/base
  (require (for-syntax racket/base mcp))
  (begin-for-syntax
    (schema Label String)
    (resource (document [id Label]) #:uri "phase:///{id}" id)
    (tool (echo [id Label]) (text-result id))
    (provide Label document echo)))
(require (rename-in (submod "." provider)
                    [Label ImportedLabel] [document imported-document] [echo imported-echo]))
;; Values created at phase one cross a module export and renamed import before
;; a different transformer references them. The assertion runs at ordinary test
;; phase; a broken imported binding instead makes module compilation fail.
(define-syntax (imported-results stx)
  #`'#,(list (hash-ref ImportedLabel 'type)
            (resource-uri (imported-document "a b"))
            ((tool-descriptor-handler imported-echo) (hasheq 'id "ok"))))
(check-equal? (imported-results)
              (list "string" "phase:///a%20b"
                    (hasheq 'resultType "complete" 'content (list (hasheq 'type "text" 'text "ok")))))
