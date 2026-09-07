#lang racket/base
(require rackunit mcp/authorization)
(define resource "https://api.example/mcp")
(define issuer "https://auth.example/tenant1")
(define expected
  '("https://auth.example/.well-known/oauth-authorization-server/tenant1"
    "https://auth.example/.well-known/openid-configuration/tenant1"
    "https://auth.example/tenant1/.well-known/openid-configuration"))
(check-equal? (authorization-metadata-urls issuer) expected)
(check-equal? (authorization-metadata-urls "https://auth.example")
  '("https://auth.example/.well-known/oauth-authorization-server"
    "https://auth.example/.well-known/openid-configuration"))
(check-equal? (car (authorization-metadata-urls "https://[::1]:8443/tenant"))
              "https://[::1]:8443/.well-known/oauth-authorization-server/tenant")
(check-exn exn:fail? (lambda () (authorization-metadata-urls "https://auth.example/tenant?other")))
(define prm (protected-resource-metadata resource (list issuer)))
(define as (hasheq 'issuer issuer 'authorization_endpoint "https://auth.example/authorize"
                   'token_endpoint "https://auth.example/token" 'response_types_supported '("code")
                   'code_challenge_methods_supported '("S256")
                   'jwks_uri "https://auth.example/keys" 'subject_types_supported '("public")
                   'id_token_signing_alg_values_supported '("RS256")))
(define path-metadata "https://api.example/.well-known/oauth-protected-resource/mcp")
(define root-metadata "https://api.example/.well-known/oauth-protected-resource")
(define seen '())
(define (fetch url)
  (set! seen (append seen (list url)))
  (cond [(equal? url root-metadata) prm] [(equal? url (caddr expected)) as] [else #f]))
(define-values (r a) (discover-authorization-for-resource resource fetch))
(check-equal? r prm)
(check-equal? a as)
(check-equal? seen (append (list path-metadata root-metadata) expected))
;; Stop as soon as a valid document is obtained.
(set! seen '())
(define-values (_r _a)
  (discover-authorization-for-resource resource
    (lambda (url) (set! seen (append seen (list url)))
      (cond [(equal? url path-metadata) prm] [(equal? url (car expected)) as] [else (error 'test "unexpected fallback")]))))
(check-equal? seen (list path-metadata (car expected)))
;; An advertised metadata URL takes precedence and is not replaced on failure.
(set! seen '())
(check-exn #rx"no metadata" (lambda ()
  (discover-authorization-for-resource resource
    (lambda (url) (set! seen (cons url seen)) #f) #:metadata-url "https://metadata.example/resource.json")))
(check-equal? seen '("https://metadata.example/resource.json"))
;; Never fall back past a document that lies about its protected resource.
(set! seen '())
(check-exn #rx"resource identifier mismatch" (lambda ()
  (discover-authorization-for-resource resource
    (lambda (url) (set! seen (cons url seen)) (hash-set prm 'resource "https://other.example/mcp")))))
(check-equal? seen (list path-metadata))
(set! seen '())
(check-exn #rx"issuer mismatch" (lambda ()
  (discover-authorization-for-resource resource
    (lambda (url) (set! seen (append seen (list url)))
      (if (equal? url path-metadata) prm (hash-set as 'issuer "https://other.example"))))))
(check-equal? seen (list path-metadata (car expected)))
(check-exn #rx"network failure" (lambda () (discover-authorization-for-resource resource (lambda (_) (error 'fetch "network failure")))))
(check-exn #rx"code response" (lambda ()
  (discover-authorization-for-resource resource
    (lambda (url) (if (equal? url path-metadata) prm (hash-remove as 'response_types_supported))))))
;; Issuer selection is explicit and restricted to the advertised list.
(define selected "https://second.example")
(define-values (_selected-resource selected-as)
  (discover-authorization-for-resource resource
    (lambda (url)
      (cond [(equal? url path-metadata) (hash-set prm 'authorization_servers (list issuer selected))]
            [(equal? url (car (authorization-metadata-urls selected))) (hash-set as 'issuer selected)]
            [else (error 'test "wrong issuer fetched")])) #:select-issuer cadr))
(check-equal? (hash-ref selected-as 'issuer) selected)
(check-exn #rx"not advertised" (lambda ()
  (discover-authorization-for-resource resource (lambda (_) prm) #:select-issuer (lambda (_) selected))))
;; Queries remain part of resource identity but are absent from discovery URLs.
(define query-resource "https://api.example/mcp?tenant=1")
(define-values (qr qa)
  (discover-authorization-for-resource query-resource
    (lambda (url) (cond [(equal? url path-metadata) (hash-set prm 'resource query-resource)]
                       [(equal? url (car expected)) as] [else (error 'test "bad query URL")]))))
(check-equal? (hash-ref qr 'resource) query-resource)
;; The explicit-URL API can enforce the same expected identity.
(check-exn #rx"resource identifier mismatch" (lambda ()
  (discover-authorization root-metadata (lambda (_) prm) #:resource "https://other.example/mcp")))
