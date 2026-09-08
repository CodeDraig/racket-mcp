#lang racket/base
(require racket/file racket/runtime-path mcp/json mcp/schema)
(define-runtime-path fixtures "../vendor/json-schema-tests/tests/draft2020-12/optional")

;; Optional regex compatibility is counted independently of the core suite.
;; Every selected case must pass; errors are reported, never silently skipped.
(module+ main
  (define passed 0)
  (define failed 0)
  (for ([name '("ecmascript-regex.json" "non-bmp-regex.json")])
    (define groups (string->json (file->string (build-path fixtures name))))
    (for* ([group (in-list groups)] [test (in-list (hash-ref group 'tests))])
      (define got
        (with-handlers ([exn:fail? (lambda (e) (exn-message e))])
          (valid? (hash-ref group 'schema) (hash-ref test 'data))))
      (if (equal? got (hash-ref test 'valid))
          (set! passed (add1 passed))
          (begin
            (set! failed (add1 failed))
            (printf "FAIL ~a: ~a / ~a (~a)\n" name (hash-ref group 'description)
                    (hash-ref test 'description) got)))))
  (printf "~a optional regex cases passed; ~a failed or unsupported\n" passed failed)
  (unless (zero? failed) (exit 1)))
