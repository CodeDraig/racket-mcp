#lang racket/base
(require racket/list racket/string net/url "json.rkt" "authorization.rkt"
         "private/oauth-http-request.rkt" "private/oauth-uri-policy.rkt")
(provide register-oauth-client! validate-oauth-registration-response
         oauth-registration-result? oauth-registration-result-issuer
         oauth-registration-result-metadata)
;; Metadata may contain a secret. Do not print it through the result value.
(struct oauth-registration-result (issuer metadata))
(define (bad field) (error 'oauth-registration "invalid or incompatible registration field: ~a" field))
(define (nonempty-string? v) (and (string? v) (positive? (string-length v))))
(define (strings? v) (and (list? v) (pair? v) (andmap nonempty-string? v)
                          (= (length v) (length (remove-duplicates v)))))
(define (absolute-uri? v)
  (and (nonempty-string? v)
       (let ([u (string->url v)]) (and (url-scheme u) (not (url-user u)) (not (url-fragment u))))))
(define (redirect? v)
  (and (absolute-uri? v)
       (let ([u (string->url v)])
         (cond [(equal? (url-scheme u) "http")
                (member (url-host u) '("localhost" "127.0.0.1" "::1"))]
               [(equal? (url-scheme u) "https") (url-host u)]
               [else #t]))))
(define (metadata! value)
  ;; Round-trip checks JSON representability and snapshots mutable input.
  ;; JSON objects use the SDK's symbol-keyed hash representation.
  (define encoded (json->string value))
  (define m (string->json encoded #:max-bytes (bytes-length (string->bytes/utf-8 encoded))))
  (unless (hash? m) (bad 'metadata))
  (for ([(key v) (in-hash m)])
    (define base (string->symbol (car (string-split (symbol->string key) "#" #:trim? #f))))
    (cond [(memq base '(client_name software_id software_version software_statement client_id client_secret))
           (unless (nonempty-string? v) (bad key))]
          [(memq base '(client_uri logo_uri tos_uri policy_uri jwks_uri))
           (unless (absolute-uri? v) (bad key))]
          [(eq? key 'contacts)
           (unless (and (list? v) (andmap nonempty-string? v)) (bad key))]
          [(memq key '(grant_types response_types))
           (unless (strings? v) (bad key))]
          [(eq? key 'scope)
           (unless (and (nonempty-string? v)
                        (andmap nonempty-string? (string-split v " " #:trim? #f))
                        (for/and ([c (in-string v)])
                          (define n (char->integer c))
                          (or (= n 32) (and (<= 33 n 126) (not (memv n '(34 92)))))))
             (bad key))]
          [(memq key '(client_id_issued_at client_secret_expires_at))
           (unless (exact-nonnegative-integer? v) (bad key))]))
  (define redirects (hash-ref m 'redirect_uris #f))
  (unless (and (strings? redirects) (andmap redirect? redirects)) (bad 'redirect_uris))
  (unless (member (hash-ref m 'token_endpoint_auth_method "client_secret_basic")
                  '("none" "client_secret_basic" "client_secret_post"))
    (bad 'token_endpoint_auth_method))
  (when (hash-has-key? m 'application_type)
    (unless (member (hash-ref m 'application_type) '("native" "web")) (bad 'application_type)))
  (when (hash-has-key? m 'jwks)
    (define jwks (hash-ref m 'jwks))
    (unless (and (hash? jwks) (list? (hash-ref jwks 'keys #f))
                 (andmap hash? (hash-ref jwks 'keys))) (bad 'jwks))
    (when (hash-has-key? m 'jwks_uri) (bad 'jwks_uri)))
  (unless (member "authorization_code" (hash-ref m 'grant_types '("authorization_code"))) (bad 'grant_types))
  (unless (member "code" (hash-ref m 'response_types '("code"))) (bad 'response_types))
  m)
(define (request-metadata! value)
  (define m (metadata! value))
  (for ([key '(client_id client_secret client_id_issued_at client_secret_expires_at)])
    (when (hash-has-key? m key) (bad key)))
  (unless (hash-has-key? m 'application_type) (bad 'application_type))
  m)
(define (validate-oauth-registration-response requested response)
  (define request (request-metadata! requested))
  (define result (metadata! response))
  (when (hash-has-key? result 'error) (bad 'error))
  (when (and (hash-has-key? result 'client_secret_expires_at)
             (not (hash-has-key? result 'client_secret))) (bad 'client_secret_expires_at))
  (unless (nonempty-string? (hash-ref result 'client_id #f)) (bad 'client_id))
  (when (hash-has-key? result 'client_secret)
    (unless (hash-has-key? result 'client_secret_expires_at) (bad 'client_secret_expires_at)))
  (unless (or (equal? (hash-ref result 'token_endpoint_auth_method "client_secret_basic") "none")
              (nonempty-string? (hash-ref result 'client_secret #f))) (bad 'client_secret))
  ;; Require the requested callbacks and grants to remain usable.
  ;; Display metadata and extension values may legitimately be replaced by AS.
  (unless (equal? (sort (hash-ref request 'redirect_uris) string<?)
                  (sort (hash-ref result 'redirect_uris) string<?)) (bad 'redirect_uris))
  (for ([key '(grant_types response_types)] [default '(("authorization_code") ("code"))])
    (for ([needed (in-list (hash-ref request key default))])
      (unless (member needed (hash-ref result key default)) (bad key))))
  (when (hash-has-key? request 'software_statement)
    (unless (equal? (hash-ref request 'software_statement) (hash-ref result 'software_statement #f))
      (bad 'software_statement)))
  result)
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
