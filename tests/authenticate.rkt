#lang racket/base
(require rackunit mcp/authorization)
(define parsed
  (parse-authenticate '("Basic realm=\"simple\", Newauth realm=\"apps\", type=1, title=\"Login to \\\"apps\\\"\""
                        "bEaReR resource_metadata=\"https://example.com/meta?x=1,2\", scope=\"read write\"")))
(check-equal? (map authentication-challenge-scheme parsed) '("basic" "newauth" "bearer"))
(check-equal? (authentication-challenge-parameters (cadr parsed))
              (hash "realm" "apps" "type" "1" "title" "Login to \"apps\""))
(check-equal? (hash-ref (authentication-challenge-parameters (caddr parsed)) "resource_metadata")
              "https://example.com/meta?x=1,2")
(check-equal? (authentication-challenge-token68 (car (parse-authenticate '("Negotiate YWJjZA==")))) "YWJjZA==")
(check-equal? (authentication-challenge-parameters (car (parse-authenticate '("Bearer ReAlM = \"\", SCOPE=read"))))
              (hash "realm" "" "scope" "read"))
(check-equal? (map authentication-challenge-scheme (parse-authenticate '(",, Bearer, , Basic realm=x, ")))
              '("bearer" "basic"))
(check-equal? (authentication-challenge-parameters (car (parse-authenticate '("Bearer realm=x" "scope=read"))))
              (hash "realm" "x" "scope" "read"))
(for ([bad '("Bearer realm=x, REALM=y" "Bearer realm=\"unfinished" "Bearer realm=x\r\nInjected: x"
              "realm=x" "Bearer realm=\"x\"junk" "Bearer abc==, scope=x" "Bearer\trealm=x" "Bearer a=bad value")])
  (check-exn exn:fail? (lambda () (parse-authenticate (list bad)))))
(check-exn #rx"byte limit" (lambda () (parse-authenticate '("Bearer") #:max-bytes 5)))
(check-equal? (parse-authenticate '()) '())
