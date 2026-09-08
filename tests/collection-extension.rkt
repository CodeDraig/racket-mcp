#lang racket/base
(require rackunit mcp)

(module interface mcp/lang
  (require (rename-in "../examples/extensions/collection.rkt" [collection catalog]))
  (provide evaluations helper-values)
  ;; These host bindings must not capture names introduced by the extension.
  (define data 'host-data)
  (define query 'host-query)
  (define id 'host-id)
  (define prefix 'host-prefix)
  (define context 'host-context)
  (define helper-values (list data query id prefix context))
  (define evaluations (box 0))
  (catalog books #:uri "book:///{id}"
    #:entries (begin (set-box! evaluations (add1 (unbox evaluations)))
                     (hash "a b" "First book" "two" "Second book")))
  (catalog articles #:uri "article:///{id}"
    #:entries (begin (set-box! evaluations (add1 (unbox evaluations)))
                     (hash "a b" "First article" "essay" "Second article"))))

(require (submod "." interface))
(check-equal? (unbox evaluations) 2)
(check-equal? helper-values '(host-data host-query host-id host-prefix host-context))
(define rt (make-runtime (view mcp-interface #:namespace "library/"
                              #:uris (hash "book:///{id}" "archive:///{id}"))))
(dynamic-wind void
  (lambda ()
    (define (call method params) (dispatch rt method (hash-set params '_meta (request-meta))))
    (check-equal?
     (sort (hash-ref (call "tools/call" (hasheq 'name "library/search-books" 'arguments (hasheq 'query "book"))) 'structuredContent) string<?)
     '("a b" "two"))
    (check-equal?
     (hash-ref (call "tools/call" (hasheq 'name "library/search-articles" 'arguments (hasheq 'query "book"))) 'structuredContent)
     '())
    (define read (call "resources/read" (hasheq 'uri "archive:///a%20b")))
    (check-equal? (hash-ref (car (hash-ref read 'contents)) 'text) "First book")
    (check-equal? (hash-ref (car (hash-ref read 'contents)) 'uri) "archive:///a%20b")
    (define complete (call "completion/complete"
      (hasheq 'ref (hasheq 'type "ref/resource" 'uri "archive:///{id}")
              'argument (hasheq 'name "id" 'value "t"))))
    (check-equal? (hash-ref (hash-ref complete 'completion) 'values) '("two"))
    (check-equal? (unbox evaluations) 2))
  (lambda () (custodian-shutdown-all (runtime-custodian rt))))
