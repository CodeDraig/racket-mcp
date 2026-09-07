#lang racket/base
(require racket/list net/url)
(provide validate-authorization-metadata!)
(define string-lists
  '(scopes_supported response_types_supported response_modes_supported grant_types_supported
    code_challenge_methods_supported token_endpoint_auth_methods_supported
    token_endpoint_auth_signing_alg_values_supported revocation_endpoint_auth_methods_supported
    revocation_endpoint_auth_signing_alg_values_supported introspection_endpoint_auth_methods_supported
    introspection_endpoint_auth_signing_alg_values_supported ui_locales_supported acr_values_supported
    subject_types_supported id_token_signing_alg_values_supported id_token_encryption_alg_values_supported
    id_token_encryption_enc_values_supported userinfo_signing_alg_values_supported
    userinfo_encryption_alg_values_supported userinfo_encryption_enc_values_supported
    request_object_signing_alg_values_supported request_object_encryption_alg_values_supported
    request_object_encryption_enc_values_supported display_values_supported claim_types_supported
    claims_supported claims_locales_supported))
(define boolean-fields
  '(client_id_metadata_document_supported authorization_response_iss_parameter_supported
    claims_parameter_supported request_parameter_supported request_uri_parameter_supported
    require_request_uri_registration))
(define (url! value key #:issuer? [issuer? #f] #:secure? [secure? #t])
  (unless (string? value) (error 'authorization-metadata "~a must be a URL string" key))
  (define u (string->url value))
  (unless (and (url-scheme u) (url-host u) (not (url-user u)) (not (url-fragment u))
               (or (not secure?) (equal? (url-scheme u) "https"))
               (or (not issuer?) (null? (url-query u))))
    (error 'authorization-metadata "invalid URL for ~a" key)))
(define (validate-authorization-metadata! metadata issuer #:oidc? [oidc? #f])
  (unless (and (hash? metadata) (equal? (hash-ref metadata 'issuer #f) issuer))
    (error 'authorization-metadata "authorization server issuer mismatch"))
  (url! issuer 'issuer #:issuer? #t)
  (for ([key '(authorization_endpoint token_endpoint)]) (url! (hash-ref metadata key #f) key))
  (for ([key (in-list string-lists)] #:when (hash-has-key? metadata key))
    (define value (hash-ref metadata key))
    (unless (and (list? value) (andmap string? value))
      (error 'authorization-metadata "~a must be an array of strings" key)))
  (for ([key (in-list boolean-fields)] #:when (hash-has-key? metadata key))
    (unless (boolean? (hash-ref metadata key)) (error 'authorization-metadata "~a must be boolean" key)))
  (for ([key '(jwks_uri userinfo_endpoint registration_endpoint revocation_endpoint introspection_endpoint)]
        #:when (hash-has-key? metadata key))
    (url! (hash-ref metadata key) key))
  (for ([key '(service_documentation op_policy_uri op_tos_uri)] #:when (hash-has-key? metadata key))
    (url! (hash-ref metadata key) key #:secure? #f))
  (unless (member "code" (hash-ref metadata 'response_types_supported '()))
    (error 'authorization-metadata "authorization server must support the code response type"))
  (unless (member "authorization_code" (hash-ref metadata 'grant_types_supported '("authorization_code" "implicit")))
    (error 'authorization-metadata "authorization code grant is not supported"))
  (for ([pair '((token_endpoint_auth_methods_supported token_endpoint_auth_signing_alg_values_supported)
                (revocation_endpoint_auth_methods_supported revocation_endpoint_auth_signing_alg_values_supported)
                (introspection_endpoint_auth_methods_supported introspection_endpoint_auth_signing_alg_values_supported))])
    (define methods (hash-ref metadata (car pair) '()))
    (when (or (member "private_key_jwt" methods) (member "client_secret_jwt" methods))
      (unless (pair? (hash-ref metadata (cadr pair) '()))
        (error 'authorization-metadata "JWT client authentication requires ~a" (cadr pair)))))
  (for ([key '(token_endpoint_auth_signing_alg_values_supported revocation_endpoint_auth_signing_alg_values_supported
               introspection_endpoint_auth_signing_alg_values_supported)])
    (when (member "none" (hash-ref metadata key '()))
      (error 'authorization-metadata "none is forbidden in ~a" key)))
  (when oidc?
    (url! (hash-ref metadata 'jwks_uri #f) 'jwks_uri)
    (define subjects (hash-ref metadata 'subject_types_supported '()))
    (unless (and (pair? subjects) (andmap (lambda (v) (member v '("public" "pairwise"))) subjects))
      (error 'authorization-metadata "OIDC requires valid subject_types_supported"))
    (unless (member "RS256" (hash-ref metadata 'id_token_signing_alg_values_supported '()))
      (error 'authorization-metadata "OIDC requires RS256 in id_token_signing_alg_values_supported")))
  metadata)
