#lang racket/base
(require "clock.rkt" "private/oauth-uri-policy.rkt" racket/list racket/string "authorization.rkt" "oauth-http.rkt")
(provide make-oauth-authorizer oauth-authorizer? oauth-authorizer-resource authorize-resource!)
(struct oauth-authorizer (lock run resource))
(define (make-oauth-authorizer #:resource resource #:redirect-uri redirect #:browse browse
                               #:fetch [supplied-fetch #f] #:exchange [supplied-exchange #f]
                               #:load [load (lambda (issuer client-id resource) #f)]
                               #:save [save (lambda (issuer client-id resource credential) (void))]
                               #:pre-registered [registrations (hash)]
                               #:client-authentication [authentication-config (hash)]
                               #:allow-loopback-http? [loopback? #f]
                               #:client-metadata [document #f] #:client-metadata-url [document-url #f]
                               #:request-registration [request-registration #f]
                               #:select-issuer [select-issuer car] #:clock [clock mcp-current-seconds])
  (unless (boolean? loopback?) (raise-argument-error 'make-oauth-authorizer "boolean?" loopback?))
  (unless (hash? authentication-config)
    (raise-argument-error 'make-oauth-authorizer "issuer-keyed client authentication hash" authentication-config))
  (define authentications
    (for/hash ([(issuer authentication) (in-hash authentication-config)])
      (unless (and (oauth-client-authentication? authentication)
                   (equal? issuer (oauth-client-authentication-issuer authentication)))
        (error 'make-oauth-authorizer "client authentication must be keyed by its issuer"))
      (values (oauth-client-authentication-issuer authentication) authentication)))
  (when (and supplied-exchange (positive? (hash-count authentications)))
    (error 'make-oauth-authorizer "a custom exchange owns authentication; do not combine it with native client authentication"))
  (define-values (native-fetch native-exchange) (make-oauth-http-adapters #:allow-loopback-http? loopback?))
  (define fetch (or supplied-fetch native-fetch))
  (define exchange (or supplied-exchange native-exchange))
  (define credentials (make-hash))
  (define unsaved (make-hash))
  (define uncertain (make-hash))
  (define (covers? credential scopes)
    (for/and ([scope (in-list scopes)]) (member scope (oauth-credential-scopes credential))))
  (define (check-credential! credential issuer)
    (unless (and (oauth-credential? credential)
                 (equal? issuer (oauth-credential-issuer credential))
                 (equal? resource (oauth-credential-resource credential))
                 (string? (oauth-credential-access-token credential))
                 (regexp-match? #px"^[A-Za-z0-9._~+/-]+=*$" (oauth-credential-access-token credential))
                 (real? (oauth-credential-expires credential))
                 (< -inf.0 (oauth-credential-expires credential) +inf.0))
      (error 'authorize-resource! "stored credential does not match issuer/resource or is malformed"))
    (check-scopes! (oauth-credential-scopes credential))
    credential)
  (define (run challenges requested-scopes rejected-token reauthorize?)
    (unless (and (list? challenges) (andmap authentication-challenge? challenges))
      (raise-argument-error 'authorize-resource! "list of authentication challenges" challenges))
    (define bearers (filter (lambda (c) (equal? (authentication-challenge-scheme c) "bearer")) challenges))
    (when (> (length bearers) 1) (error 'authorize-resource! "multiple Bearer challenges; select one explicitly"))
    (define challenge (and (pair? bearers) (car bearers)))
    (when (and challenge (authentication-challenge-token68 challenge))
      (error 'authorize-resource! "Bearer challenge must use authentication parameters"))
    (define parameters (if challenge (authentication-challenge-parameters challenge) (hash)))
    (define-values (protected metadata)
      (discover-authorization-for-resource resource fetch
        #:metadata-url (hash-ref parameters "resource_metadata" #f) #:select-issuer select-issuer))
    (define scopes
      (check-scopes!
       (cond [(hash-has-key? parameters "scope") (string-split (hash-ref parameters "scope") " ")]
             [requested-scopes requested-scopes]
             [else (hash-ref protected 'scopes_supported '())])))
    (define registration
      (select-oauth-registration metadata resource redirect scopes #:pre-registered registrations
        #:client-metadata document #:client-metadata-url document-url #:request-registration request-registration))
    (define issuer (oauth-registration-issuer registration))
    (define client-id (oauth-registration-client-id registration))
    (define authentication (hash-ref authentications issuer #f))
    (when authentication
      (unless (equal? client-id (oauth-client-authentication-client-id authentication))
        (error 'authorize-resource! "client authentication does not match the selected registration"))
      (define supported (hash-ref metadata 'token_endpoint_auth_methods_supported '("client_secret_basic")))
      (unless (member (symbol->string (oauth-client-authentication-method authentication)) supported)
        (error 'authorize-resource! "authorization server does not support the configured client authentication method")))
    (define selected-exchange
      (if authentication
          (let-values ([(fetch exchange)
                        (make-oauth-http-adapters #:allow-loopback-http? loopback?
                          #:client-authentication authentication #:token-endpoint (hash-ref metadata 'token_endpoint))])
            exchange)
          exchange))
    (define key (list issuer client-id resource))
    (when (hash-has-key? unsaved key)
      (save issuer client-id resource (hash-ref unsaved key))
      (hash-remove! unsaved key))
    (when (and (hash-ref uncertain key #f) (not reauthorize?))
      (error 'authorize-resource! "previous token exchange failed; explicit reauthorization is required"))
    (define existing (and (not reauthorize?) (hash-ref credentials key (lambda () (load issuer client-id resource)))))
    (define (obtain thunk)
      (with-handlers ([(lambda (_) #t) (lambda (e) (hash-set! uncertain key #t) (raise e))]) (thunk)))
    (when existing (check-credential! existing issuer))
    (define rejected? (and existing rejected-token (equal? rejected-token (oauth-credential-access-token existing))))
    (define step-up? (and (equal? (hash-ref parameters "error" #f) "insufficient_scope")
                          (or (not existing) (not rejected-token) rejected?)))
    (define credential
      (cond [(and existing (not rejected?) (not step-up?)
                  (> (oauth-credential-expires existing) (clock)) (covers? existing scopes)) existing]
            [(and existing (not step-up?) (covers? existing scopes) (oauth-credential-refresh-token existing))
             ;; Failure or an uncertain exchange is surfaced; never retry a
             ;; refresh token or silently fall through to another browser flow.
             (obtain (lambda () (refresh-credential registration existing metadata selected-exchange #:clock clock)))]
            [else
             (define-values (url pending) (begin-authorization registration metadata))
             (define response (browse url))
             (unless response (error 'authorize-resource! "authorization cancelled by application"))
             (obtain (lambda () (finish-authorization pending response selected-exchange #:clock clock)))]))
    (with-handlers ([(lambda (_) #t) (lambda (e) (hash-set! uncertain key #t) (raise e))])
      (check-credential! credential issuer)
      (unless (covers? credential scopes) (error 'authorize-resource! "authorization did not grant the required scopes")))
    (unless (eq? credential existing)
      ;; Retain a successful exchange even if persistence fails. The next call
      ;; retries persistence, not the consumed code or rotating refresh token.
      (hash-set! credentials key credential)
      (hash-set! unsaved key credential)
      (save issuer client-id resource credential)
      (hash-remove! unsaved key))
    (hash-remove! uncertain key)
    (hash-set! credentials key credential)
    credential)
  (oauth-authorizer (make-semaphore 1)
    (lambda arguments
      (parameterize ([current-oauth-loopback-http? loopback?]) (apply run arguments))) resource))
(define (authorize-resource! authorizer #:challenges [challenges '()] #:scopes [scopes #f]
                             #:rejected-token [rejected-token #f] #:reauthorize? [reauthorize? #f])
  (call-with-semaphore (oauth-authorizer-lock authorizer)
    (lambda () ((oauth-authorizer-run authorizer) challenges scopes rejected-token reauthorize?))))
