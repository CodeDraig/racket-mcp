#lang racket/base
(require racket/async-channel racket/list racket/port racket/string net/url net/uri-codec
         "json.rkt" "private/http-wire.rkt")
(provide make-oauth-http-adapters (struct-out exn:fail:oauth-http))
(struct exn:fail:oauth-http exn:fail (status headers body) #:transparent)
(define (make-oauth-http-adapters #:timeout [timeout 30]
                                 #:max-response-bytes [body-limit 1048576]
                                 #:max-header-bytes [header-limit 65536]
                                 #:allow-loopback-http? [loopback? #f])
  (unless (and (real? timeout) (< 0 timeout +inf.0))
    (raise-argument-error 'make-oauth-http-adapters "positive finite timeout" timeout))
  (for ([limit (in-list (list body-limit header-limit))])
    (unless (exact-positive-integer? limit)
      (raise-argument-error 'make-oauth-http-adapters "exact-positive-integer? byte limit" limit)))
  (define (request endpoint method payload)
    (define u (string->url endpoint))
    (define tls? (equal? (url-scheme u) "https"))
    (unless (and (url-host u) (not (url-user u)) (not (url-fragment u))
                 (or tls? (and loopback? (equal? (url-scheme u) "http")
                               (member (url-host u) '("127.0.0.1" "::1")))))
      (error 'oauth-http "endpoint requires HTTPS without user information or fragment"))
    (define owner (make-custodian))
    (define result (make-async-channel 1))
    (dynamic-wind void
      (lambda ()
        (parameterize ([current-custodian owner])
          (thread
           (lambda ()
             (with-handlers ([(lambda (_) #t) (lambda (e) (async-channel-put result (cons 'error e)))])
               (define relative (url->string (struct-copy url u [scheme #f] [user #f] [host #f] [port #f])))
               (define target (if (string-prefix? relative "/") relative (string-append "/" relative)))
               (define-values (status headers in)
                 (bounded-http-sendrecv (url-host u) target #:ssl? tls?
                   #:port (or (url-port u) (if tls? 443 80)) #:method method
                   #:headers (append '("Accept: application/json")
                                     (if (equal? method "POST") '("Content-Type: application/x-www-form-urlencoded") '()))
                   #:data payload #:max-header-bytes header-limit))
               (define body (port->bytes (make-limited-input-port in (add1 body-limit))))
               (when (> (bytes-length body) body-limit) (error 'oauth-http "response byte limit exceeded"))
               (define code (string->number (cadr (regexp-match #px"^HTTP/[0-9.]+ ([0-9]{3})" (bytes->string/latin-1 status)))))
               (define answer
                 (cond [(and (equal? method "GET") (memv code '(404 405))) #f]
                       [(not (= code 200))
                        (raise (exn:fail:oauth-http (format "OAuth HTTP request failed (~a)" code)
                                                   (current-continuation-marks) code headers body))]
                       [else
                        (define content-types
                          (for/list ([h (in-list headers)]
                                     #:do [(define m (regexp-match #px#"(?i:^content-type:)[\t ]*(.*)$" h))]
                                     #:when m)
                            (bytes->string/latin-1 (cadr m))))
                        (unless (and (= (length content-types) 1)
                                     (regexp-match? #px"(?i:^application/json[\t ]*(?:;|$))" (car content-types)))
                          (error 'oauth-http "expected application/json metadata or token response"))
                        (define json (string->json (bytes->string/utf-8 body) #:max-bytes body-limit))
                        (unless (hash? json) (error 'oauth-http "expected a JSON object"))
                        json]))
               (async-channel-put result (cons 'ok answer))))))
        (define outcome (sync/timeout timeout result))
        (unless outcome (error 'oauth-http "request timed out"))
        (if (eq? (car outcome) 'error) (raise (cdr outcome)) (cdr outcome)))
      ;; Includes DNS/TCP/TLS, body reader/copy worker, success, failure, timeout,
      ;; and exception/break unwinding of the caller. No request is retried or redirected.
      (lambda () (custodian-shutdown-all owner))))
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
    (request endpoint "POST" (alist->form-urlencoded (sort pairs symbol<? #:key car))))
  (values fetch exchange))
