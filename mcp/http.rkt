#lang racket/base
(require "private/failure.rkt" "private/http-request.rkt" (only-in web-server/private/connection-manager connection-custodian connection-i-port) (only-in racket/tcp tcp-addresses) "clock.rkt" racket/string racket/list racket/port racket/async-channel net/base64 net/url
         web-server/http web-server/web-server web-server/servlet-dispatch web-server/safety-limits
         "subscription.rkt" "authorization.rkt" "private/http-wire.rkt" "private/sse.rkt" "private/wire-message.rkt" "private/request-message.rkt" "private/progress.rkt" "private/subscription-client.rkt" "json.rkt" "runtime.rkt" "descriptor.rkt" "stdio.rkt" "header-schema.rkt")
(provide serve-http make-http-handler encode-header-value decode-header-value request-headers
         make-http-client http-client-request http-client-call (struct-out http-client)
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
(define (encode-header-value value)
  (if (and (regexp-match? #px"^[ -~]*$" value) (equal? value (string-trim value))
           (not (and (string-prefix? value "=?base64?") (string-suffix? value "?=")))) value
      (string-append "=?base64?" (bytes->string/utf-8 (base64-encode (string->bytes/utf-8 value) #"")) "?=")))
(define (decode-header-value value)
  (if (and (string-prefix? value "=?base64?") (string-suffix? value "?="))
      (let* ([encoded (substring value 9 (- (string-length value) 2))]
             [raw (base64-decode (string->bytes/utf-8 encoded))])
        (unless (equal? encoded (bytes->string/utf-8 (base64-encode raw #""))) (mcp-error -32020 "Malformed header encoding"))
        (bytes->string/utf-8 raw)) value))
(define (request-headers method params)
  (append (list (cons "Content-Type" "application/json") (cons "Accept" "application/json, text/event-stream")
                (cons "MCP-Protocol-Version" protocol-version) (cons "Mcp-Method" method))
          (if (member method '("tools/call" "prompts/get" "resources/read"))
              (list (cons "Mcp-Name" (encode-header-value (hash-ref params (if (equal? method "resources/read") 'uri 'name))))) '())))
(define (json-response status body [headers '()])
  (response/full status #f (current-seconds) #"application/json" headers
                 (if body (list (string->bytes/utf-8 (json->string body))) '())))
(define (response-status result)
  (define code (hash-ref (hash-ref result 'error (hasheq)) 'code #f))
  (cond [(equal? code -32001) 403] [(equal? code -32601) 404]
        [(member code '(-32602 -32600 -32020 -32021 -32022)) 400] [else 200]))
(define (request-response rt message principal stream? keepalive limit stream-after)
  (define request (start-http-request rt message principal limit))
  (with-handlers ([(lambda (_) #t) (lambda (failure) (stop-http-request! request) (raise failure))])
    (define first (and (not stream?) (http-request-next request stream-after)))
    (cond [(and first (eq? (http-event-kind first) 'failure)) (raise (http-event-value first))]
          [(and first (eq? (http-event-kind first) 'done))
           (stop-http-request! request)
           (define result (http-event-value first))
           (response/full (response-status result) #f (current-seconds)
                          #"application/json" '() (list (http-event-bytes first)))]
          [else
           (response/output (lambda (out) (write-http-request request out keepalive first))
             #:mime-type #"text/event-stream"
             #:headers (list (header #"Cache-Control" #"no-cache") (header #"X-Accel-Buffering" #"no")))])))
(define ephemeral-origin-policy (gensym 'ephemeral-origin))
(define current-ephemeral-origin (make-parameter #f))
(define (origin-url host port)
  (format "http://~a:~a" (if (and (string? host) (string-contains? host ":")) (format "[~a]" host) host) port))
(define (make-http-handler rt #:origins [origins '()] #:authenticate [authenticate #f] #:sse? [sse? #f] #:max-bytes [max-bytes 1048576]
                           #:keepalive-seconds [keepalive 15] #:max-response-bytes [response-limit 1048576]
                           #:stream-after [stream-after 0.05]
                           #:resource-metadata [metadata #f] #:resource-metadata-url [metadata-url #f])
  (when (and metadata-url (not metadata)) (error 'make-http-handler "metadata URL requires resource metadata"))
  (when metadata
    (protected-resource-metadata (hash-ref metadata 'resource) (hash-ref metadata 'authorization_servers)
                                 #:scopes (hash-ref metadata 'scopes_supported '()))
    (set! metadata (string->json (json->string metadata)))
    (set! metadata-url (or metadata-url (protected-resource-metadata-url (hash-ref metadata 'resource))))
    (bearer-challenge metadata-url)
    (when (pair? (url-query (string->url metadata-url)))
      (error 'make-http-handler "metadata URL must not contain a query"))
    (unless authenticate (error 'make-http-handler "protected resource requires an authentication adapter")))
  (define metadata-path (and metadata-url (url-path (string->url metadata-url))))
  (define authenticate-request (or authenticate (lambda (_) 'local)))
  (define (challenge [scopes '()] [kind #f])
    (header #"WWW-Authenticate"
      (string->bytes/utf-8 (if metadata-url (bearer-challenge metadata-url #:scopes scopes #:error kind)
                              (if kind (string-append "Bearer error=\"" kind "\", scope=\"" (string-join scopes " ") "\"") "Bearer")))))
  (unless (and (real? keepalive) (< 0 keepalive +inf.0)) (raise-argument-error 'make-http-handler "positive finite real?" keepalive))
  (unless (and (rational? stream-after) (>= stream-after 0))
    (raise-argument-error 'make-http-handler "finite nonnegative stream-after seconds" stream-after))
  (unless (exact-positive-integer? response-limit) (raise-argument-error 'make-http-handler "exact-positive-integer?" response-limit))
  (lambda (req)
    (parameterize ([current-mcp-clock (runtime-clock rt)])
    (define id missing)
    (define headers (request-headers/raw req))
    (define (get-header key)
      (define found (filter (lambda (h) (string-ci=? (bytes->string/utf-8 (header-field h)) key)) headers))
      (when (> (length found) 1) (mcp-error -32020 "Duplicate request header"))
      (and (pair? found) (string-trim (bytes->string/utf-8 (header-value/raw (car found))))))
    (with-handlers ([exn:fail:mcp? (lambda (e)
                                    (define detail (hasheq 'code (exn:fail:mcp-code e) 'message (exn-message e)))
                                    (define body (hasheq 'jsonrpc "2.0" 'error (if (exn:fail:mcp-data e) (hash-set detail 'data (exn:fail:mcp-data e)) detail)))
                                    (define data (exn:fail:mcp-data e))
                                    (define scopes (and (hash? data) (hash-ref data 'requiredScopes #f)))
                                    (json-response (if (= (exn:fail:mcp-code e) -32001) 403 400)
                                                   (if (request-id? id) (hash-set body 'id id) body)
                                                   (if scopes (list (challenge scopes "insufficient_scope")) '())))]
                    [exn:fail? (lambda (_) (json-response 400 (hasheq 'jsonrpc "2.0" 'error (hasheq 'code -32700 'message "Invalid request body"))))])
      (define origin (get-header "Origin"))
      (cond [(and metadata-path (equal? (url-path (request-uri req)) metadata-path))
             (if (bytes=? (request-method req) #"GET")
                 (json-response 200 metadata (list (header #"Access-Control-Allow-Origin" #"*")))
                 (json-response 405 #f (list (header #"Allow" #"GET"))))]
            [(and origin (not (member origin (if (eq? origins ephemeral-origin-policy) (list (current-ephemeral-origin)) origins)))) (json-response 403 #f)]
            [(not (bytes=? (request-method req) #"POST")) (json-response 405 #f (list (header #"Allow" #"POST")))]
            [else
             (define principal (authenticate-request headers))
             (define accepted?
               (and principal
                    (or (not metadata)
                        (and (verified-principal? principal)
                             (member (verified-principal-issuer principal) (hash-ref metadata 'authorization_servers))
                             (member (hash-ref metadata 'resource)
                                     (let ([aud (verified-principal-audience principal)]) (if (list? aud) aud (list aud))))
                             (> (verified-principal-expiry principal) (mcp-current-seconds))))))
             (cond [(not accepted?) (json-response 401 #f (list (challenge)))]
                   [else
                    (unless (regexp-match? #px"^application/json(?:;|$)" (or (get-header "Content-Type") "")) (mcp-error -32600 "Expected application/json"))
                    (define raw (or (request-post-data/raw req) #""))
                    (when (> (bytes-length raw) max-bytes) (mcp-error -32600 "Request body limit exceeded"))
                    (define message (string->json (bytes->string/utf-8 raw) #:max-bytes max-bytes))
                    (when (hash? message) (set! id (hash-ref message 'id missing)))
                    (check-client-message message)
                    (define method (hash-ref message 'method))
                    (define params (hash-ref message 'params (hasheq)))
                    (when (hash-has-key? message 'id)
                      (define accept (or (get-header "Accept") ""))
                      (unless (and (string-contains? accept "application/json") (string-contains? accept "text/event-stream")) (mcp-error -32600 "Accept must include JSON and SSE"))
                      (define meta (validate-request-meta params #:version? #f))
                      (unless (equal? (get-header "MCP-Protocol-Version") (hash-ref meta 'io.modelcontextprotocol/protocolVersion #f)) (mcp-error -32020 "Protocol version header does not match body"))
                      (unless (equal? (get-header "Mcp-Method") method) (mcp-error -32020 "Method header does not match body"))
                      (when (member method '("tools/call" "prompts/get" "resources/read"))
                        (unless (equal? (decode-header-value (or (get-header "Mcp-Name") ""))
                                        (hash-ref params (if (equal? method "resources/read") 'uri 'name) #f))
                          (mcp-error -32020 "Name header does not match body"))))
                    (when (equal? method "tools/call")
                      (define descriptor (findf (lambda (d) (equal? (tool-descriptor-name d) (hash-ref params 'name #f))) (interface-descriptor-tools (runtime-interface rt))))
                      (when descriptor
                        (define schema (tool-descriptor-input-schema descriptor))
                        (define expected (mirrored-headers schema (hash-ref params 'arguments (hasheq))))
                        (for ([binding (in-list (header-bindings schema))])
                          (define actual (get-header (header-binding-name binding)))
                          (define required (assoc (header-binding-name binding) expected))
                          (unless (equal? (and actual (decode-header-value actual)) (and required (cdr required)))
                            (mcp-error -32020 "Annotated parameter header does not match body")))))
                    ;; Scope preflight happens before starting SSE; runtime authorization
                    ;; enforces the same callback again for local and resumed execution.
                    (define needed ((runtime-required-scopes rt) method params))
                    (unless (or (null? needed) (scopes-allow? principal needed))
                      (mcp-error -32001 "Insufficient scope" (hasheq 'requiredScopes needed)))
                    (cond [(not (hash-has-key? message 'id)) (dispatch-message rt message #:principal principal) (json-response 202 #f)]
                          [else
                           (request-response rt message principal
                             (or sse? (equal? method "subscriptions/listen")
                                 (hash-has-key? (hash-ref params '_meta (hasheq)) 'progressToken))
                             keepalive response-limit stream-after)])])])))))
(define header-value/raw header-value)
(define (serve-http rt #:port [port 8000] #:host [host "127.0.0.1"] #:origins [origins #f]
                    #:authenticate [authenticate #f] #:sse? [sse? #f] #:confirmation [confirmation #f]
                    #:keepalive-seconds [keepalive 15] #:max-response-bytes [response-limit 1048576]
                    #:stream-after [stream-after 0.05]
                    #:resource-metadata [metadata #f] #:resource-metadata-url [metadata-url #f])
  (define dispatcher
    (dispatch/servlet
      (make-http-handler rt #:origins (or origins (if (zero? port) ephemeral-origin-policy (list (origin-url host port))))
        #:authenticate authenticate #:sse? sse? #:keepalive-seconds keepalive
        #:max-response-bytes response-limit #:stream-after stream-after
        #:resource-metadata metadata #:resource-metadata-url metadata-url)))
  (serve #:dispatch (lambda (connection request)
                      (define resolved-origin
                        (and (not origins) (zero? port)
                             (let-values ([(local-address local-port remote-address remote-port)
                                           (tcp-addresses (connection-i-port connection) #t)])
                               (origin-url host local-port))))
                      (parameterize ([current-http-request-custodian (connection-custodian connection)]
                                     [current-ephemeral-origin resolved-origin])
                        (call-with-http-request-scope (lambda () (dispatcher connection request)))))
         #:port port #:listen-ip host #:confirmation-channel confirmation
         #:safety-limits (make-safety-limits #:max-request-body-length 1048576)))
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
