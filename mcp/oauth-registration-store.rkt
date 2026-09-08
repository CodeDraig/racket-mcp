#lang racket/base
(require db file/sha1 "storage.rkt" "json.rkt" "clock.rkt" "authorization.rkt"
         "oauth-registration.rkt" (submod "oauth-registration.rkt" private)
         "private/oauth-uri-policy.rkt")
(provide ensure-oauth-registration!)
(define (ensure-oauth-registration! store authorization-metadata requested
                                   #:clock [clock mcp-current-seconds]
                                   #:allow-loopback-http? [loopback? #f]
                                   #:retry-uncertain? [retry? #f]
                                   #:register [register
                                               (lambda (metadata fields)
                                                 (register-oauth-client! metadata fields
                                                   #:allow-loopback-http? loopback?))])
  (unless (and (boolean? loopback?) (boolean? retry?))
    (error 'ensure-oauth-registration! "expected boolean policy options"))
  (when (current-store-connection)
    (error 'ensure-oauth-registration! "registration must run outside a storage transaction"))
  ;; Snapshot inputs before a network adapter or another thread can mutate them.
  (define metadata (string->json (json->string authorization-metadata)))
  (define issuer (and (hash? metadata) (hash-ref metadata 'issuer #f)))
  (parameterize ([current-oauth-loopback-http? loopback?])
    (validate-authorization-metadata! metadata issuer))
  (define fields (request-metadata! requested))
  (define profile (json->string fields))
  (define worker-key (bytes->hex-string (sha256-bytes
    (string->bytes/utf-8 (json->string (list "oauth-registration-v1" issuer fields))))))
  (define (now)
    (define t (clock))
    (unless (exact-nonnegative-integer? t)
      (error 'ensure-oauth-registration! "clock must return nonnegative integer Unix seconds"))
    t)
  (define (expired? m)
    (define expiry (hash-ref m 'client_secret_expires_at 0))
    (and (positive? expiry) (<= expiry (now))))
  (define conn (state-store-connection store))
  (define (transaction thunk) (store-transaction store thunk))
  (define answer #f)
  (define locked?
    (call-with-instance-worker store worker-key
      (lambda ()
        (transaction
          (lambda ()
            (query-exec conn "CREATE TABLE IF NOT EXISTS oauth_registrations_v1 (issuer TEXT NOT NULL, profile TEXT NOT NULL, status TEXT NOT NULL, metadata TEXT, updated INTEGER NOT NULL, PRIMARY KEY(issuer,profile))")))
        (define row
          (transaction (lambda ()
            (query-maybe-row conn "SELECT status,metadata FROM oauth_registrations_v1 WHERE issuer=? AND profile=?" issuer profile))))
        (define cached
          (and row (equal? (vector-ref row 0) "ready")
               (validate-oauth-registration-response fields (string->json (vector-ref row 1)))))
        (cond
          [(and cached (not (expired? cached)))
           (set! answer (oauth-registration-result issuer cached))]
          [else
           (when (and row (not (equal? (vector-ref row 0) "ready")) (not retry?))
             (error 'ensure-oauth-registration! "previous registration is uncertain; explicit #:retry-uncertain? #t is required"))
           ;; Commit intent before calling the AS. A killed worker cannot cause
           ;; a later caller to silently repeat an uncertain mutation.
           (transaction (lambda ()
             (query-exec conn "INSERT INTO oauth_registrations_v1(issuer,profile,status,metadata,updated) VALUES(?,?,'pending',NULL,?) ON CONFLICT(issuer,profile) DO UPDATE SET status='pending',metadata=NULL,updated=excluded.updated"
                         issuer profile (now))))
           (define result (register metadata fields))
           (unless (and (oauth-registration-result? result)
                        (equal? issuer (oauth-registration-result-issuer result)))
             (error 'ensure-oauth-registration! "registration adapter returned a foreign issuer or invalid result"))
           (define registered
             (validate-oauth-registration-response fields (oauth-registration-result-metadata result)))
           (when (expired? registered)
             (error 'ensure-oauth-registration! "authorization server returned an expired client secret"))
           (transaction (lambda ()
             (query-exec conn "UPDATE oauth_registrations_v1 SET status='ready',metadata=?,updated=? WHERE issuer=? AND profile=?"
                         (json->string registered) (now) issuer profile)))
           (set! answer (oauth-registration-result issuer registered))]))))
  (unless locked? (error 'ensure-oauth-registration! "registration is already in progress"))
  answer)
