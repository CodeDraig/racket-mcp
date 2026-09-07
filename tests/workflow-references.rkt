#lang racket/base
(require rackunit racket/list mcp)
(define executions 0)
(resource (document [id String]) #:uri "doc:///{id}" id)
(workflow (checkpoint-ref) #:version "1"
  (checkpoint [uri String] (resource-uri (document "checkpoint")))
  (text-result uri))
(workflow (input-ref) #:version "1"
  (await-input [answer Any]
    (hasheq 'mode "form" 'message (resource-uri (document "input"))
            'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (text-result "done"))
(workflow (effect-ref) #:version "1"
  (perform [saved Any] #:adapter save #:policy idempotent
    (resource-uri (document "effect")))
  (text-result "done"))
(workflow (branch-ref) #:version "1"
  (if (resource-ref? (document "branch")) (text-result "yes") (text-result "no")))
(workflow (complete-ref [id String]) #:version "1"
  (begin0 (hasheq 'resultType "complete" 'content (list (link (document id))))
          (set! executions (add1 executions))))
(prompt (prompt-ref [id String]) #:workflow "1"
  (role "user" (link (document id))))
(resource (resource-referrer [id String]) #:uri "referrer:///{id}" #:workflow "1"
  (resource-uri (document id)))
(workflow (shadow-ref [document String]) #:version "1"
  (text-result document))
(define tools (list checkpoint-ref input-ref effect-ref branch-ref complete-ref shadow-ref))
(define iface (make-interface #:tools tools #:resources (list document resource-referrer) #:prompts (list prompt-ref)))
(define graph (interface-resource-references iface))
(check-equal? executions 0)
(check-equal? (hash-count graph) 7)
(for ([source (in-list (append (take tools 5) (list prompt-ref resource-referrer)))])
  (check-equal? (hash-ref graph source) (list document)))
(check-false (hash-has-key? graph shadow-ref))
(check-exn #rx"references an absent resource: document" (lambda () (view iface #:exclude '("document"))))
(check-equal? executions 0)
(define mapped (view iface #:namespace "public/" #:uris (hash "doc:///{id}" "public:///{id}")))
(define store (open-memory-store))
(define rt (make-runtime mapped #:store store))
(define result (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "public/complete-ref" 'arguments (hasheq 'id "a b"))))
(check-equal? (hash-ref (car (hash-ref result 'content)) 'uri) "public:///a%20b")
(check-equal? executions 1)
(custodian-shutdown-all (runtime-custodian rt))
(close-store! store)
