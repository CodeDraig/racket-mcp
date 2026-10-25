#lang racket/base
(require racket/string
         net/url
         (only-in web-server/private/connection-manager connection-custodian connection-i-port)
         (only-in racket/tcp tcp-addresses)
         web-server/http
         web-server/web-server
         web-server/servlet-dispatch
         web-server/safety-limits
         "../clock.rkt"
         "../authorization.rkt"
         "../json.rkt"
         "../runtime.rkt"
         "../descriptor.rkt"
         "../header-schema.rkt"
         "http-request.rkt"
         "http-headers.rkt"
         "request-message.rkt" "failure.rkt" "runtime-policy.rkt")
(provide serve-http make-http-handler)
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
    (define phase 'headers)
    (define headers (request-headers/raw req))
    (define (get-header key)
      (define found (filter (lambda (h) (string-ci=? (bytes->string/utf-8 (header-field h)) key)) headers))
      (when (> (length found) 1) (mcp-error -32020 "Duplicate request header"))
      (and (pair? found) (string-trim (bytes->string/utf-8 (header-value (car found))))))
    (with-handlers ([exn:fail:mcp? (lambda (e)
                                    (define detail (hasheq 'code (exn:fail:mcp-code e) 'message (exn-message e)))
                                    (define body (hasheq 'jsonrpc "2.0" 'error (if (exn:fail:mcp-data e) (hash-set detail 'data (exn:fail:mcp-data e)) detail)))
                                    (define data (exn:fail:mcp-data e))
                                    (define scopes (and (hash? data) (hash-ref data 'requiredScopes #f)))
                                    (json-response (if (= (exn:fail:mcp-code e) -32001) 403 400)
                                                   (if (request-id? id) (hash-set body 'id id) body)
                                                   (if scopes (list (challenge scopes "insufficient_scope")) '())))]
                    [non-break-failure? (lambda (failure)
                      (eprintf "HTTP request failed: phase=~a category=~a\n" phase
                        (cond [(exn:fail:contract? failure) 'contract] [(exn:fail? failure) 'failure]
                              [(exn? failure) 'exception] [else 'raised-value]))
                      (json-response 500 (hasheq 'jsonrpc "2.0" 'error (hasheq 'code -32603 'message "Internal error"))))])
      (define origin (get-header "Origin"))
      (cond [(and metadata-path (equal? (url-path (request-uri req)) metadata-path))
             (if (bytes=? (request-method req) #"GET")
                 (json-response 200 metadata (list (header #"Access-Control-Allow-Origin" #"*")))
                 (json-response 405 #f (list (header #"Allow" #"GET"))))]
            [(and origin (not (member origin (if (eq? origins ephemeral-origin-policy) (list (current-ephemeral-origin)) origins)))) (json-response 403 #f)]
            [(not (bytes=? (request-method req) #"POST")) (json-response 405 #f (list (header #"Allow" #"POST")))]
            [else
             (set! phase 'authentication)
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
                    (set! phase 'decoding)
                    (define message
                      (with-handlers ([exn:fail? (lambda (_failure) (mcp-error -32700 "Invalid request body"))])
                        (string->json (bytes->string/utf-8 raw) #:max-bytes max-bytes)))
                    (set! phase 'request-validation)
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
                    (set! phase 'authorization)
                    (check-task-ownership! (runtime-store rt) method params principal)
                    (define needed ((runtime-required-scopes rt) method params))
                    (unless (or (null? needed) (scopes-allow? principal needed))
                      (mcp-error -32001 "Insufficient scope" (hasheq 'requiredScopes needed)))
                    (cond [(not (hash-has-key? message 'id)) (dispatch-message rt message #:principal principal) (json-response 202 #f)]
                          [else
                           (begin (set! phase 'dispatch) (request-response rt message principal
                             (or sse? (equal? method "subscriptions/listen")
                                 (hash-has-key? (hash-ref params '_meta (hasheq)) 'progressToken))
                             keepalive response-limit stream-after))])])])))))
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
