#lang racket/base
(require rackunit mcp)
(define reads 0)
(resource (document [id String]) #:uri "doc:///{id}" (set! reads (add1 reads)) id)
(test-case "ordinary reference constructor enforces the resource call contract"
  (check-equal? (resource-ref document '("a b")) (document "a b"))
  (check-equal? (resource-uri (resource-ref document '("a b"))) "doc:///a%20b")
  (for ([arguments (list '() '("a" "b") '(17) #f)])
    (check-exn exn:fail? (lambda () (resource-ref document arguments))))
  (check-exn exn:fail:contract? (lambda () (resource-ref 'not-a-resource '()))))
(test-case "dynamic references reject ambiguous mounting instead of choosing list order"
  (define base (make-interface #:resources (list document)))
  (define first (view base #:namespace "first/" #:uris (hash "doc:///{id}" "first:///{id}")))
  (define second (view base #:namespace "second/" #:uris (hash "doc:///{id}" "second:///{id}")))
  (for ([interface (list (mount-interfaces first second) (mount-interfaces second first))])
    (parameterize ([current-interface interface])
      (check-exn #rx"ambiguous" (lambda () (resource-uri (document "x"))))
      (check-exn #rx"ambiguous" (lambda () (link (document "x")))))))
(test-case "unique remapping and removal retain the same reference behavior"
  (define base (make-interface #:resources (list document)))
  (define mapped (view base #:namespace "public/" #:uris (hash "doc:///{id}" "public:///{id}")))
  (parameterize ([current-interface mapped])
    (check-equal? (hash-ref (link (resource-ref document '("a b"))) 'uri) "public:///a%20b")
    (check-equal? (hash-ref (link (document "a b")) 'name) "public/document"))
  (parameterize ([current-interface (make-interface)])
    (check-exn #rx"absent" (lambda () (resource-uri (document "x"))))))

(test-case "dynamic ambiguity reaches protocol errors before reading either resource"
  (define base (make-interface #:resources (list document)))
  (define first (view base #:namespace "first/" #:uris (hash "doc:///{id}" "first:///{id}")))
  (define second (view base #:namespace "second/" #:uris (hash "doc:///{id}" "second:///{id}")))
  (for ([render (list link embed)])
    ;; This ordinary procedure deliberately has no statically collected edge.
    (define operation
      (make-tool "dynamic" '()
        (lambda (_) (hasheq 'resultType "complete" 'content (list (render (document "x")))))))
    (define runtime
      (make-runtime (mount-interfaces first second (make-interface #:tools (list operation)))))
    (dynamic-wind void
      (lambda ()
        (define result
          (dispatch-message runtime
            (hasheq 'jsonrpc "2.0" 'id 1 'method "tools/call"
              'params (hasheq '_meta (request-meta) 'name "dynamic"))))
        (check-false (hash-has-key? result 'result))
        (check-equal? (hash-ref (hash-ref result 'error) 'code) -32603)
        (check-equal? reads 0))
      (lambda () (custodian-shutdown-all (runtime-custodian runtime))))))
