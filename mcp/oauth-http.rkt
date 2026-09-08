#lang racket/base
(require racket/list net/url net/uri-codec net/base64
         "private/oauth-http-request.rkt" "private/oauth-uri-policy.rkt" "private/oauth-client-auth.rkt")
(provide make-oauth-http-adapters (struct-out exn:fail:oauth-http)
         oauth-client-authentication oauth-client-authentication?
         oauth-client-authentication-issuer oauth-client-authentication-client-id
         oauth-client-authentication-method)
(define (make-oauth-http-adapters #:timeout [timeout 30]
                                 #:max-response-bytes [body-limit 1048576]
                                 #:max-header-bytes [header-limit 65536]
                                 #:allow-loopback-http? [loopback? #f]
                                 #:client-authentication [authentication #f]
                                 #:token-endpoint [token-endpoint #f])
  (unless (boolean? loopback?)
    (raise-argument-error 'make-oauth-http-adapters "boolean?" loopback?))
  (unless (or (not authentication) (oauth-client-authentication? authentication))
    (raise-argument-error 'make-oauth-http-adapters "OAuth client authentication or #f" authentication))
  (when authentication
    (unless (and (string? token-endpoint)
                 (oauth-secure-url? (string->url token-endpoint) #:loopback? loopback?))
      (error 'make-oauth-http-adapters "client authentication requires an approved token endpoint"))
    (set! token-endpoint (string->immutable-string token-endpoint)))
  (define request (make-oauth-http-request timeout body-limit header-limit loopback?))
  (define (fetch endpoint) (request endpoint "GET" ""))
  (define (exchange endpoint fields)
    (unless (and (hash? fields)
                 (for/and ([(key value) (in-hash fields)])
                   (and (or (symbol? key) (string? key)) (string? value))))
      (raise-argument-error 'oauth-exchange "hash of string form values" fields))
    (define pairs
      (for/list ([(key value) (in-hash fields)])
        (cons (if (symbol? key) key (string->symbol key)) value)))
    (unless (= (length pairs) (length (remove-duplicates (map car pairs))))
      (error 'oauth-exchange "duplicate normalized form parameter"))
    (define headers '())
    (when authentication
      (unless (equal? endpoint token-endpoint)
        (error 'oauth-exchange "token endpoint changed after client authentication was configured"))
      (for ([name '(client_secret client_assertion client_assertion_type)])
        (when (assq name pairs) (error 'oauth-exchange "conflicting client authentication form parameter")))
      (define client-id (oauth-client-authentication-client-id authentication))
      (define supplied-id (assq 'client_id pairs))
      (when (and supplied-id (not (equal? (cdr supplied-id) client-id)))
        (error 'oauth-exchange "client ID does not match authentication configuration"))
      (set! pairs (filter (lambda (pair) (not (eq? (car pair) 'client_id))) pairs))
      (case (oauth-client-authentication-method authentication)
        [(client_secret_basic)
         (define credentials
           (string-append (form-urlencoded-encode client-id) ":"
                          (form-urlencoded-encode (oauth-client-authentication-secret authentication))))
         (set! headers (list (string-append "Authorization: Basic "
           (bytes->string/latin-1 (base64-encode (string->bytes/utf-8 credentials) #"")))))]
        [(client_secret_post)
         (set! pairs (list* (cons 'client_id client-id)
                           (cons 'client_secret (oauth-client-authentication-secret authentication)) pairs))]
        [else (set! pairs (cons (cons 'client_id client-id) pairs))]))
    (request endpoint "POST" (alist->form-urlencoded (sort pairs symbol<? #:key car)) headers))
  (values fetch exchange))
