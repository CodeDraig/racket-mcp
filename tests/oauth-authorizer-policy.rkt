#lang racket/base
(require rackunit net/url mcp/authorization mcp/oauth mcp/oauth-http)
(define redirect "http://localhost:3080/callback")
(for ([base '("http://localhost:8888" "http://127.0.0.1:8888" "http://[::1]:8888")])
  (define resource (string-append base "/mcp"))
  (define issuer (string-append base "/issuer"))
  (define exchanges 0)
  (define browsers 0)
  (define now 0)
  (define (fetch url)
    (if (regexp-match? #rx"oauth-protected-resource" url)
        (hasheq 'resource resource 'authorization_servers (list issuer) 'scopes_supported '("read"))
        (hasheq 'issuer issuer 'authorization_endpoint (string-append base "/authorize")
                'token_endpoint (string-append base "/token") 'response_types_supported '("code")
                'code_challenge_methods_supported '("S256"))))
  (define (make [loopback? #f])
    (make-oauth-authorizer #:resource resource #:redirect-uri redirect #:allow-loopback-http? loopback?
      #:pre-registered (hash issuer (oauth-registration issuer "id" redirect resource '()))
      #:fetch fetch #:clock (lambda () now)
      #:browse (lambda (url)
        (set! browsers (add1 browsers))
        ;; Nested secure authorizers must reset the enclosing test policy.
        (check-exn #rx"HTTPS" (lambda () (authorize-resource! (make))))
        (check-exn #rx"HTTPS" (lambda () (client-id-metadata-document
          (string-append base "/client.json") "client" (list redirect))))
        (hasheq 'state (cdr (assq 'state (url-query (string->url url)))) 'iss issuer 'code "code"))
      #:exchange (lambda (url fields)
        (check-equal? url (string-append base "/token"))
        (check-equal? (hash-ref fields 'resource) resource)
        (set! exchanges (add1 exchanges))
        (hasheq 'token_type "Bearer" 'access_token (format "token-~a" exchanges)
                'refresh_token "refresh" 'expires_in 10 'scope "read"))))
  (check-exn #rx"HTTPS" (lambda () (authorize-resource! (make))))
  (define auth (make #t))
  (check-equal? (oauth-credential-access-token (authorize-resource! auth)) "token-1")
  (set! now 11)
  (check-equal? (oauth-credential-access-token (authorize-resource! auth)) "token-2")
  (check-equal? exchanges 2)
  (check-equal? browsers 1)
  (check-exn #rx"HTTPS" (lambda () (protected-resource-metadata-url resource))))

(define issuer "https://issuer.example")
(define resource "https://api.example/mcp")
(define browsers 0)
(define (fetch url)
  (if (regexp-match? #rx"oauth-protected-resource" url)
      (hasheq 'resource resource 'authorization_servers (list issuer))
      (hasheq 'issuer issuer 'authorization_endpoint "https://issuer.example/authorize"
              'token_endpoint "https://issuer.example/token" 'response_types_supported '("code")
              'code_challenge_methods_supported '("S256") 'token_endpoint_auth_methods_supported '("none"))))
(define (configured authentication)
  (make-oauth-authorizer #:resource resource #:redirect-uri redirect #:fetch fetch
    #:pre-registered (hash issuer (oauth-registration issuer "client" redirect resource '()))
    #:client-authentication (hash issuer authentication)
    #:browse (lambda (_) (set! browsers (add1 browsers)) (error 'test "unexpected browser"))))
(check-exn #rx"selected registration"
  (lambda () (authorize-resource! (configured (oauth-client-authentication issuer "other" 'none #f)))))
(check-exn #rx"does not support"
  (lambda () (authorize-resource! (configured (oauth-client-authentication issuer "client" 'client_secret_basic "secret")))))
(check-equal? browsers 0)
(check-exn #rx"keyed by its issuer"
  (lambda () (configured (oauth-client-authentication "https://other.example" "client" 'none #f))))
(check-exn #rx"custom exchange"
  (lambda () (make-oauth-authorizer #:resource resource #:redirect-uri redirect #:browse void
    #:exchange void #:client-authentication (hash issuer (oauth-client-authentication issuer "client" 'none #f)))))
(check-exn exn:fail?
  (lambda () (make-oauth-authorizer #:resource resource #:redirect-uri redirect #:browse void #:allow-loopback-http? 'yes)))
