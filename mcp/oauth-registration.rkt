#lang racket/base
(require "json.rkt" "private/oauth-metadata.rkt" "private/oauth-registration-metadata.rkt"
         "private/oauth-http-request.rkt" "private/oauth-uri-policy.rkt")
(provide register-oauth-client! validate-oauth-registration-response
         oauth-registration-result? oauth-registration-result-issuer
         oauth-registration-result-metadata)

(define (register-oauth-client! authorization-metadata requested
                               #:initial-access-token [token #f]
                               #:timeout [timeout 30]
                               #:max-response-bytes [body-limit 1048576]
                               #:max-header-bytes [header-limit 65536]
                               #:allow-loopback-http? [loopback? #f])
  (define request (make-oauth-http-request timeout body-limit header-limit loopback?))
  (define metadata (string->json (json->string authorization-metadata)))
  (unless (hash? metadata) (bad 'authorization-metadata))
  (define issuer (hash-ref metadata 'issuer #f))
  (parameterize ([current-oauth-loopback-http? loopback?])
    (validate-authorization-metadata! metadata issuer))
  (define endpoint (hash-ref metadata 'registration_endpoint #f))
  (unless (string? endpoint) (bad 'registration_endpoint))
  (define fields (request-metadata! requested))
  (unless (or (not token) (and (string? token) (regexp-match? #px"^[A-Za-z0-9._~+/-]+=*$" token)))
    (bad 'initial-access-token))
  (define response
    (request endpoint "POST" (string->bytes/utf-8 (json->string fields))
             (if token (list (string-append "Authorization: Bearer " token)) '())
             #:content-type "application/json" #:success-status 201))
  (oauth-registration-result issuer (validate-oauth-registration-response fields response)))

;; SDK persistence reconstructs only after validating the stored metadata.
(module+ private (provide oauth-registration-result request-metadata!))
