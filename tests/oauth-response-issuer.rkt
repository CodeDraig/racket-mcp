#lang racket/base
(require rackunit mcp/authorization)

;; MCP 2026-07-28 authorization response validation: all four table rows,
;; including the distinct false and omitted metadata cases.
(define issuer "https://issuer.example")
(define registration
  (oauth-registration issuer "client" "http://localhost:3080/callback"
                      "https://resource.example/mcp" '("read")))
(define metadata
  (hasheq 'issuer issuer 'authorization_endpoint "https://issuer.example/authorize"
          'token_endpoint "https://issuer.example/token"
          'code_challenge_methods_supported '("S256")))
(for ([support '(omitted #f #t)])
  (define-values (_ pending)
    (begin-authorization registration
      (if (eq? support 'omitted) metadata
          (hash-set metadata 'authorization_response_iss_parameter_supported support))))
  (define response (hasheq 'state (oauth-pending-state pending) 'code "fixture-code"))
  (for ([returned (list 'omitted issuer "https://other.example" "https://ISSUER.example"
                       "https://issuer.example/" "https://issuer.example:443"
                       "https://%69ssuer.example" "" #f 'null)])
    (test-case (format "advertised ~s, returned issuer ~s" support returned)
      (define exchanges 0)
      (define (exchange endpoint body)
        (set! exchanges (add1 exchanges))
        (check-equal? endpoint "https://issuer.example/token")
        (check-equal? (hash-ref body 'code) "fixture-code")
        (check-equal? (hash-ref body 'code_verifier) (oauth-pending-verifier pending))
        (hasheq 'access_token "fixture-token" 'token_type "Bearer" 'expires_in 60))
      (define answer (if (eq? returned 'omitted) response (hash-set response 'iss returned)))
      (cond
        [(or (equal? returned issuer)
             (and (eq? returned 'omitted) (not (eq? support #t))))
         (define credential (finish-authorization pending answer exchange))
         (check-equal? (oauth-credential-issuer credential) issuer)
         (check-equal? (oauth-credential-access-token credential) "fixture-token")
         (check-equal? exchanges 1)]
        [else
         (check-exn #rx"issuer mismatch"
           (lambda () (finish-authorization pending answer exchange)))
         (check-equal? exchanges 0)])))
  (for ([returned (list 'omitted issuer)])
    (test-case (format "state and error guards with support ~s, issuer ~s" support returned)
      (define exchanges 0)
      (define (exchange _endpoint _body) (set! exchanges (add1 exchanges)))
      (define answer (if (eq? returned 'omitted) response (hash-set response 'iss returned)))
      (check-exn #rx"state mismatch"
        (lambda () (finish-authorization pending (hash-set answer 'state "wrong") exchange)))
      (check-exn (if (and (eq? support #t) (eq? returned 'omitted))
                     #rx"issuer mismatch" #rx"authorization declined")
        (lambda ()
          (finish-authorization pending
            (hash-set (hash-remove answer 'code) 'error "access_denied") exchange)))
      (check-equal? exchanges 0))))
