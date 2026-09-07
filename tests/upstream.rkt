#lang racket/base
(require rackunit mcp mcp/upstream)
(define calls 0)
(define source (make-runtime (make-interface #:tools (list (make-tool "echo" '() (lambda (v) (set! calls (add1 calls)) (structured-result v)) #:input-schema (hasheq 'type "object" 'additionalProperties Integer) #:raw? #t)))))
(define (remote method params) (hasheq 'result (dispatch source method (hash-set params '_meta (request-meta)))))
(define snapshot (capture-snapshot remote))
(check-equal? calls 0)
(define adapter (make-runtime (make-upstream-interface snapshot remote)))
(check-equal? (hash-ref (dispatch adapter "tools/call" (hasheq '_meta (request-meta) 'name "echo" 'arguments (hasheq 'extra 7))) 'structuredContent) (hasheq 'extra 7))
(check-equal? calls 1)
(define changed (hash-set snapshot 'tools/list (hasheq 'tools '())))
(check-exn exn:fail? (lambda () (check-upstream-compatibility! changed remote)))

;; A pinned peer fixture supplies multi-resource contents and protocol links.
;; Structured application JSON deliberately resembles a link and stays untouched.
(define seen '())
(define doc-uri "remote:///doc/{id}")
(define discover (hasheq 'resultType "complete" 'supportedVersions '("2026-07-28")
  'capabilities (hasheq 'tools (hasheq) 'resources (hasheq) 'prompts (hasheq) 'completions (hasheq))))
(define lists
  (hasheq 'server/discover discover
    'tools/list (hasheq 'tools (list (hasheq 'name "show" 'inputSchema (hasheq 'type "object"))))
    'resources/list (hasheq 'resources (list (hasheq 'name "index" 'uri "remote:///index")))
    'resources/templates/list (hasheq 'resourceTemplates (list (hasheq 'name "doc" 'uriTemplate doc-uri)))
    'prompts/list (hasheq 'prompts (list (hasheq 'name "read" 'arguments
      (list (hasheq 'name "id" 'required #t) (hasheq 'name "style")))))))
(define raw-link (hasheq 'type "resource_link" 'name "doc" 'uri "remote:///doc/a%20b"))
(define (peer method params)
  (set! seen (cons (cons method params) seen))
  (hasheq 'result
    (hash-ref lists (string->symbol method)
      (lambda ()
        (case (string->symbol method)
          [(completion/complete) (hasheq 'completion (hasheq 'values '("alpha") 'total 200 'hasMore #t))]
          [(resources/read) (hasheq 'resultType "complete" 'contents
            (list (hasheq 'uri (hash-ref params 'uri) 'text "First" 'mimeType "text/markdown")
                  (hasheq 'uri "remote:///index" 'blob "AP8=" 'mimeType "image/png")))]
          [(tools/call) (hasheq 'resultType "complete" 'content (list raw-link)
                           'structuredContent raw-link)]
          [(prompts/get) (hasheq 'resultType "complete" 'description "Peer description"
            'messages (list (hasheq 'role "user" 'content raw-link)
                            (hasheq 'role "assistant" 'content (hasheq 'type "resource" 'resource
                              (hasheq 'uri "remote:///index" 'text "Index")))))]
          [else (error 'peer "unexpected method ~a" method)])))))
(define domain-snapshot (capture-snapshot peer))
(set! seen '())
(define domain (make-upstream-interface domain-snapshot peer))
(check-equal? seen '())
(define domain-rt (make-runtime (view domain #:namespace "local-" #:rename (hash "read" "review")
  #:uris (hash doc-uri "local:///doc/{id}" "remote:///index" "local:///index"))))
(define (domain-call method params)
  (dispatch domain-rt method (hash-set params '_meta (request-meta))))
(define read-result (domain-call "resources/read" (hasheq 'uri "local:///doc/a%20b")))
(check-equal? (map (lambda (v) (hash-ref v 'uri)) (hash-ref read-result 'contents))
              '("local:///doc/a%20b" "local:///index"))
(check-equal? (map (lambda (v) (hash-ref v 'mimeType)) (hash-ref read-result 'contents))
              '("text/markdown" "image/png"))
(check-equal? (hash-ref (cadr (hash-ref read-result 'contents)) 'blob) "AP8=")
(check-equal? (hash-ref (cdar seen) 'uri) "remote:///doc/a%20b")
(define shown (domain-call "tools/call" (hasheq 'name "local-show")))
(check-equal? (hash-ref (car (hash-ref shown 'content)) 'uri) "local:///doc/a%20b")
(check-equal? (hash-ref (car (hash-ref shown 'content)) 'name) "local-doc")
(check-equal? (hash-ref shown 'structuredContent) raw-link)
(define prompted (domain-call "prompts/get" (hasheq 'name "local-review" 'arguments (hasheq 'id "a b"))))
(check-equal? (hash-ref prompted 'description) "Peer description")
(check-equal? (hash-ref (cdar seen) 'arguments) (hasheq 'id "a b"))
(check-equal? (hash-ref (hash-ref (hash-ref (cadr (hash-ref prompted 'messages)) 'content) 'resource) 'uri)
              "local:///index")
(check-exn exn:fail? (lambda () (domain-call "prompts/get" (hasheq 'name "local-review"))))
(check-exn exn:fail? (lambda () (domain-call "prompts/get" (hasheq 'name "local-review" 'arguments (hasheq 'id 3)))))
(define removed (make-runtime (view domain #:exclude '("doc"))))
(check-exn #rx"absent from the interface"
  (lambda () (dispatch removed "tools/call" (hasheq '_meta (request-meta) 'name "show"))))

;; Complex URI syntax requires an explicit inverse, never a guessed matcher.
(define complex-uri "remote:///search{?q}")
(define complex-snapshot (hash-set domain-snapshot 'resources/templates/list
  (hasheq 'resourceTemplates (list (hasheq 'name "search" 'uriTemplate complex-uri)))))
(check-exn #rx"explicit matcher" (lambda () (make-upstream-interface complex-snapshot peer)))
(define (complex-peer method params)
  (if (equal? method "resources/templates/list")
      (hasheq 'result (hash-ref complex-snapshot 'resources/templates/list))
      (peer method params)))
(define complex-domain (make-upstream-interface complex-snapshot complex-peer
  #:templates (hash complex-uri (upstream-template-adapter (list (argument 'q String #f #f))
    (lambda (uri) (and (equal? uri "remote:///search?q=hi") (hasheq 'q "hi")))))))
(define complex-rt (make-runtime complex-domain))
(check-equal? (hash-ref (car (hash-ref (dispatch complex-rt "resources/read"
  (hasheq '_meta (request-meta) 'uri "remote:///search?q=hi")) 'contents)) 'text) "First")
(define completion-context (hasheq 'arguments (hasheq 'style "brief")))
(define completed (domain-call "completion/complete"
  (hasheq 'ref (hasheq 'type "ref/prompt" 'name "local-review")
          'argument (hasheq 'name "id" 'value "a") 'context completion-context)))
(check-equal? (hash-ref completed 'completion) (hasheq 'values '("alpha") 'total 200 'hasMore #t))
(check-equal? (hash-ref (cdar seen) 'ref) (hasheq 'type "ref/prompt" 'name "read"))
(check-equal? (hash-ref (cdar seen) 'context) completion-context)
(void (domain-call "completion/complete" (hasheq 'ref (hasheq 'type "ref/resource" 'uri "local:///doc/{id}")
  'argument (hasheq 'name "id" 'value "a"))))
(check-equal? (hash-ref (cdar seen) 'ref) (hasheq 'type "ref/resource" 'uri doc-uri))
(check-exn #rx"discovery changed"
  (lambda () (check-upstream-compatibility!
    (hash-set domain-snapshot 'server/discover (hash-set discover 'supportedVersions '("other"))) peer)))
(check-exn #rx"discovery changed"
  (lambda () (check-upstream-compatibility!
    (hash-set domain-snapshot 'server/discover (hash-set discover 'capabilities (hasheq))) peer)))
(for ([rt (list source adapter domain-rt removed complex-rt)])
  (custodian-shutdown-all (runtime-custodian rt)))

;; Changes must be rejected before an application request executes, and callers
;; cannot mutate the pinned snapshot through a retained hash reference.
(define mutable-snapshot (hash-copy domain-snapshot))
(define detached (make-upstream-interface mutable-snapshot peer))
(hash-set! mutable-snapshot 'tools/list (hasheq 'tools '()))
(define detached-rt (make-runtime detached))
(check-equal? (hash-ref (dispatch detached-rt "tools/call" (hasheq '_meta (request-meta) 'name "show")) 'structuredContent) raw-link)
(custodian-shutdown-all (runtime-custodian detached-rt))
(define changed-calls 0)
(define (changed-peer method params)
  (when (equal? method "tools/call") (set! changed-calls (add1 changed-calls)))
  (if (equal? method "prompts/list") (hasheq 'result (hasheq 'prompts '())) (peer method params)))
(define changed-rt (make-runtime (make-upstream-interface domain-snapshot changed-peer)))
(check-exn #rx"pinned interface changed"
  (lambda () (dispatch changed-rt "tools/call" (hasheq '_meta (request-meta) 'name "show"))))
(check-equal? changed-calls 0)
(custodian-shutdown-all (runtime-custodian changed-rt))
(for ([invalid (list (hasheq 'text "missing URI")
                     (hasheq 'uri "remote:///x" 'text "a" 'blob "YQ==")
                     (hasheq 'uri "remote:///x" 'text #f 'blob "YQ==")
                     (hasheq 'uri "remote:///x" 'text "a" 'mimeType #f))])
  (check-exn exn:fail:contract? (lambda () (resource-content invalid))))

;; Two known resources may match one incoming link. Reject it before picking a
;; mounting identity; list order is not an authorization or URI mapping policy.
(define ambiguous-list (hasheq 'resourceTemplates
  (list (hasheq 'name "doc" 'uriTemplate doc-uri)
        (hasheq 'name "overlap" 'uriTemplate "remote:///{kind}/{id}"))))
(define ambiguous-snapshot (hash-set domain-snapshot 'resources/templates/list ambiguous-list))
(define (ambiguous-peer method params)
  (if (equal? method "resources/templates/list") (hasheq 'result ambiguous-list) (peer method params)))
(check-exn #rx"overlapping resource URI routes"
  (lambda () (make-upstream-interface ambiguous-snapshot ambiguous-peer)))

;; Upstream argument extraction shares the RFC parser, including dotted names.
(define dotted-snapshot
  (hash-set domain-snapshot 'resources/templates/list
    (hasheq 'resourceTemplates (list (hasheq 'name "dotted" 'uriTemplate "remote:///dotted/{9.a}")))))
(define dotted-domain (make-upstream-interface dotted-snapshot (lambda (_m _p) (error 'peer "must not connect during construction"))))
(define dotted-resource
  (findf (lambda (d) (equal? (resource-descriptor-name d) "dotted")) (interface-descriptor-resources dotted-domain)))
(check-equal? (map argument-name (resource-descriptor-arguments dotted-resource)) '(9.a))
(check-equal? (resource-uri (dotted-resource "a:b")) "remote:///dotted/a%3Ab")
