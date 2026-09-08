#lang racket/base
(require rackunit racket/port)
;; Every rejected example is authored independently of the implementation's
;; syntax classes. Expansion must retain the source of the submitted form.
(for ([body (in-list
  '("(server #:name \"one\" #:version \"1\") (server #:name \"two\" #:version \"1\")"
    "(server #:name \"one\" #:version \"1\" #:instructions \"a\" #:instructions \"b\")"
    "(tool (bad [x String #:optional #:default \"x\"]) (text-result x))"
    "(tool (bad) #:description \"a\" #:description \"b\" (text-result \"x\"))"
    "(resource (bad [id String]) #:uri \"test:///{undeclared}\" id)"
    "(resource (bad) #:uri \"test:///\" #:ttl-ms 1 #:ttl-ms 2 \"x\")"
    "(prompt (bad [x String #:codec values #:codec values]) (role \"user\" x))"
    "(workflow (bad) #:version \"1\" (text-result (checkpoint [x String] \"hidden\")))"
    "(workflow (bad) #:version \"1\" (checkpoint [x String] \"one\") (checkpoint [x String] \"two\") (text-result x))"))])
  (test-case body
    (define input (open-input-string (string-append "(module app mcp/lang\n" body "\n)")))
    (port-count-lines! input)
    (define stx (read-syntax 'authored-grammar.rkt input))
    (check-exn
      (lambda (e)
        (and (exn:fail:syntax? e)
             (for/or ([source (in-list (exn:fail:syntax-exprs e))])
               (and (equal? (syntax-source source) 'authored-grammar.rkt)
                    (exact-positive-integer? (syntax-line source))))))
      (lambda () (parameterize ([current-namespace (make-base-namespace)]) (expand stx))))))
