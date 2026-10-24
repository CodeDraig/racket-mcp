#lang racket/base
(require racket/string
         racket/port
         racket/async-channel
         net/url
         "../authorization.rkt"
         "../json.rkt"
         "../header-schema.rkt"
         "http-headers.rkt"
         "request-meta.rkt"
         "request-handle.rkt"
         "http-wire.rkt"
         "sse.rkt"
         "wire-message.rkt"
         "request-message.rkt"
         "progress.rkt"
         "subscription-client.rkt"
         "failure.rkt")
(provide make-http-client http-client-request http-client-call (struct-out http-client)
         (struct-out exn:fail:http:authorization) (struct-out exn:fail:http:timeout)
         (struct-out exn:fail:http:transport))
(struct exn:fail:http:authorization exn:fail (status headers body challenges resource request-token) #:transparent)
(struct exn:fail:http:timeout exn:fail (phase seconds) #:transparent)
(struct exn:fail:http:transport exn:fail (cause) #:transparent)
(define (check-timeout who v)
  (unless (or (not v) (and (rational? v) (positive? v)))
    (raise-argument-error who "positive finite real or #f" v)))
(define (bounded-response-body in limit)
  (define body (port->bytes (make-limited-input-port in (add1 limit))))
  (when (> (bytes-length body) limit) (error 'http-client "Response byte limit exceeded"))
  body)
(struct http-client (url token next-id lock schemas max-response-bytes max-header-bytes timeout header-timeout progress-tokens) #:mutable #:transparent)
(define (make-http-client url #:token [token #f] #:schemas [schemas (hash)] #:max-response-bytes [limit 1048576] #:max-header-bytes [header-limit 65536]
                          #:timeout [timeout 30] #:header-timeout [header-timeout 30])
  (check-timeout 'make-http-client timeout)
  (check-timeout 'make-http-client header-timeout)
  (unless (exact-positive-integer? limit) (raise-argument-error 'make-http-client "exact-positive-integer?" limit))
  (unless (exact-positive-integer? header-limit) (raise-argument-error 'make-http-client "exact-positive-integer?" header-limit))
  (define parsed (string->url url))
  (unless (and (member (url-scheme parsed) '("http" "https")) (url-host parsed) (not (url-user parsed)) (not (url-fragment parsed)))
    (raise-argument-error 'make-http-client "HTTP(S) URL without user information or fragment" url))
  (http-client parsed token 0 (make-semaphore 1) (hash-copy schemas) limit header-limit timeout header-timeout (make-hash)))
(define (http-client-request client method [params (hasheq)] #:capabilities [caps (hasheq)]
                             #:timeout [timeout (and (not (equal? method "subscriptions/listen")) (http-client-timeout client))]
                             #:header-timeout [header-timeout (http-client-header-timeout client)])
  (set! method (string->immutable-string method))
  (check-timeout 'http-client-request timeout)
  (check-timeout 'http-client-request header-timeout)
  (set! params (string->json (json->string params)))
  (define progress-token (hash-ref (hash-ref params '_meta (hasheq)) 'progressToken missing))
  (define progress-tracker (make-progress-tracker progress-token))
  (define request-caps (string->json (json->string caps)))
  (define started (current-inexact-monotonic-milliseconds))
  (define-values (id request-url request-token)
    (call-with-semaphore (http-client-lock client)
      (lambda ()
        (define captured-url (string->url (url->string (http-client-url client))))
        (define captured-token (and (http-client-token client) (string->immutable-string (http-client-token client))))
        (when (and (not (missing? progress-token)) (hash-has-key? (http-client-progress-tokens client) progress-token))
          (error 'http-client-request "progressToken already belongs to an active request"))
        (unless (missing? progress-token) (hash-set! (http-client-progress-tokens client) progress-token #t))
        (set-http-client-next-id! client (add1 (http-client-next-id client)))
        (values (http-client-next-id client)
                captured-url captured-token))))
  (define subscription-tracker (make-subscription-tracker id method params))
  (define custodian (make-custodian))
  (define ready (make-semaphore 0)) (define result (box #f)) (define notices (make-async-channel 64))
  (define finish-lock (make-semaphore 1))
  (define headers-ready (make-semaphore 0))
  (define (finish! v)
    ;; Validation has no side effects. Only the winning terminal transition can
    ;; publish discovered schemas and the result; late cancellation is a no-op.
    (define accepted
      (and (equal? method "tools/list") (hash? v) (hash-has-key? v 'result)
           (filter (lambda (tool)
                     (with-handlers ([exn:fail? (lambda (_) #f)])
                       (header-bindings (hash-ref tool 'inputSchema))
                       (unless (string? (hash-ref tool 'name)) (error 'http-client "Invalid tool name"))
                       #t))
                   (hash-ref (hash-ref v 'result) 'tools '()))))
    (define processed (if accepted (hash-set v 'result (hash-set (hash-ref v 'result) 'tools accepted)) v))
    (call-with-semaphore finish-lock
      (lambda ()
        (cond [(sync/timeout 0 (semaphore-peek-evt ready)) #f]
              [else
               (call-with-semaphore (http-client-lock client)
                 (lambda ()
                   (unless (missing? progress-token) (hash-remove! (http-client-progress-tokens client) progress-token))
                   (when accepted
                     (for ([tool (in-list accepted)])
                       (hash-set! (http-client-schemas client) (hash-ref tool 'name) (hash-ref tool 'inputSchema))))))
               (set-box! result processed)
               (semaphore-post ready)
               #t]))))
  (define (stop! reason)
    (when (finish! reason) (custodian-shutdown-all custodian)))
  (define handle (request-handle id ready result
                                (lambda () (stop! (exn:fail:request-cancelled "Request cancelled locally" (current-continuation-marks) id))) notices))
  (define worker
    (parameterize ([current-custodian custodian])
    (thread (lambda ()
              (with-handlers ([non-break-failure?
                               (lambda (failure)
                                 (finish! (if (exn? failure) failure
                                              (exn:fail:http:transport
                                                "HTTP transport raised a non-exception value"
                                                (current-continuation-marks) failure))))])
                (define u request-url)
                (define ssl? (equal? (url-scheme u) "https"))
                (define relative (url->string (struct-copy url u [scheme #f] [user #f] [host #f] [port #f] [fragment #f])))
                (define target (if (string-prefix? relative "/") relative (string-append "/" relative)))
                (define-values (status headers in)
                  (bounded-http-sendrecv (url-host u) target
                                 #:max-header-bytes (http-client-max-header-bytes client)
                                 #:ssl? ssl? #:port (or (url-port u) (if ssl? 443 80)) #:method "POST"
                                 #:headers (map (lambda (p) (string-append (car p) ": " (cdr p)))
                                                (append (request-headers method params)
                                                        (if (equal? method "tools/call")
                                                            (map (lambda (p) (cons (car p) (encode-header-value (cdr p))))
                                                                 (mirrored-headers (hash-ref (http-client-schemas client) (hash-ref params 'name) (hasheq)) (hash-ref params 'arguments (hasheq)))) '())
                                                        (if request-token (list (cons "Authorization" (string-append "Bearer " request-token))) '())))
                                 #:data (json->string (hasheq 'jsonrpc "2.0" 'id id 'method method 'params (hash-set params '_meta (request-meta #:capabilities request-caps #:extra (hash-ref params '_meta (hasheq))))))))
                (semaphore-post headers-ready)
                (dynamic-wind void
                  (lambda ()
                    (define status-code
                      (string->number (cadr (regexp-match #px"^HTTP/[0-9.]+ ([0-9]{3})" (bytes->string/latin-1 status)))))
                    (if (member status-code '(401 403))
                        (let* ([body (bounded-response-body in (http-client-max-response-bytes client))]
                               [fields (for/list ([h (in-list headers)]
                                                  #:do [(define match (regexp-match #px#"(?i:^www-authenticate:)[\t ]*(.*)$" h))]
                                                  #:when match)
                                         (bytes->string/utf-8 (cadr match)))])
                          (raise (exn:fail:http:authorization
                                  (format "HTTP authorization required (~a)" status-code)
                                  (current-continuation-marks) status-code headers body (parse-authenticate fields) (url->string request-url) request-token)))
                        (if (ormap (lambda (h) (regexp-match? #px#"(?i:^content-type:[\t ]*text/event-stream(?:[\t ]*;|[\t ]*$))" h)) headers)
                        (let ([reader (make-sse-reader in #:max-bytes (http-client-max-response-bytes client))])
                          (let loop ()
                            (define event (read-sse-event reader))
                            (when (eof-object? event) (error 'http-client "SSE closed before a response"))
                            (cond [(not (equal? (sse-event-type event) "message")) (loop)]
                                  [else
                                   (define m (string->json (sse-event-data event) #:max-bytes (http-client-max-response-bytes client)))
                                   (define kind (check-server-message m #:expected-id id))
                                   (cond [(memq kind '(response uncorrelated-error))
                                          (check-result-capabilities! m request-caps)
                                          (check-subscription-result! subscription-tracker m)
                                          (finish! m)]
                                         [(equal? (hash-ref m 'method) "notifications/cancelled")
                                          (define p (hash-ref m 'params (hasheq)))
                                          (check-cancellation-params p)
                                          (unless (and (equal? method "subscriptions/listen")
                                                       (equal? (hash-ref p 'requestId) id)
                                                       (equal? (hash-ref (hash-ref p '_meta (hasheq)) 'io.modelcontextprotocol/subscriptionId id) id))
                                            (error 'http-client "Server cancellation may only close this subscription"))
                                          (finish! m)]
                                         [else
                                          (if (equal? (hash-ref m 'method) "notifications/progress")
                                              (observe-progress! progress-tracker (hash-ref m 'params (hasheq)))
                                              (observe-subscription! subscription-tracker (hash-ref m 'method) (hash-ref m 'params (hasheq))))
                                          (unless (sync/timeout 0 (async-channel-put-evt notices m)) (error 'http-client "notification queue overflow"))
                                          (loop)])])))
                        (let ([body (bounded-response-body in (http-client-max-response-bytes client))])
                          (define m (string->json (bytes->string/utf-8 body) #:max-bytes (http-client-max-response-bytes client)))
                          (unless (memq (check-server-message m #:expected-id id) '(response uncorrelated-error))
                            (error 'http-client "Expected a JSON-RPC response"))
                          (check-result-capabilities! m request-caps)
                          (check-subscription-result! subscription-tracker m)
                          (finish! m)))))
                  (lambda () (close-input-port in))))))))
  ;; The HTTP framing reader owns a copy worker as well as the exposed port.
  ;; Reap the entire request custodian after the reader finishes, from outside it.
  (thread
   (lambda ()
     (define (deadline seconds phase)
       (if seconds
           (wrap-evt (alarm-evt (+ started (* seconds 1000)) #t) (lambda (_) phase))
           never-evt))
     (define done (wrap-evt (thread-dead-evt worker) (lambda (_) 'done)))
     (define total (deadline timeout 'request))
     (define outcome
       (sync done total (deadline header-timeout 'headers)
             (wrap-evt (semaphore-peek-evt headers-ready) (lambda (_) 'headers-ready))))
     (define terminal (if (eq? outcome 'headers-ready) (sync done total) outcome))
     (when (memq terminal '(request headers))
       (define seconds (if (eq? terminal 'request) timeout header-timeout))
       (stop! (exn:fail:http:timeout (format "HTTP ~a deadline exceeded (~a seconds)" terminal seconds)
                                    (current-continuation-marks) terminal seconds)))
     (custodian-shutdown-all custodian)))
  handle)
(define (http-client-call client method [params (hasheq)] #:capabilities [caps (hasheq)]
                          #:timeout [timeout (and (not (equal? method "subscriptions/listen")) (http-client-timeout client))]
                          #:header-timeout [header-timeout (http-client-header-timeout client)])
  (define v (sync (http-client-request client method params #:capabilities caps #:timeout timeout #:header-timeout header-timeout)))
  (if (exn? v) (raise v) v))
