#lang racket/base
(require rackunit racket/file racket/runtime-path mcp/json "../mcp/private/elicitation-format.rkt")
(define-runtime-path fixtures "../vendor/json-schema-tests/tests/draft2020-12/optional/format")
;; This exercises the private elicitation assertions, not the general validator's
;; intentionally annotation-only format vocabulary. Non-string values are ignored
;; by format; elicitation's separate type schemas still reject them where needed.
(for ([name '("date" "date-time" "email" "uri")])
  (define groups (string->json (file->string (build-path fixtures (string-append name ".json")))))
  (for* ([group (in-list groups)] [test (in-list (hash-ref group 'tests))])
    (check-equal? (elicitation-format-valid? name (hash-ref test 'data))
                  (hash-ref test 'valid)
                  (format "~a: ~a / ~s" name (hash-ref test 'description) (hash-ref test 'data)))))
