#lang racket/base
(require racket/string racket/list racket/port racket/async-channel net/base64 net/url net/http-client
         web-server/http web-server/web-server web-server/servlet-dispatch web-server/safety-limits
         "json.rkt" "runtime.rkt" "descriptor.rkt" "stdio.rkt" "header-schema.rkt")
(provide serve-http make-http-handler encode-header-value decode-header-value request-headers
         make-http-client http-client-request http-client-call (struct-out http-client))
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
(define (make-http-handler rt #:origins [origins '()] #:authenticate [authenticate (lambda (headers) 'local)] #:sse? [sse? #f] #:max-bytes [max-bytes 1048576])
  (lambda (req)
    (define id missing)
    (define headers (request-headers/raw req))
    (define (get-header key)
      (define found (filter (lambda (h) (string-ci=? (bytes->string/utf-8 (header-field h)) key)) headers))
      (when (> (length found) 1) (mcp-error -32020 "Duplicate request header"))
      (and (pair? found) (string-trim (bytes->string/utf-8 (header-value/raw (car found))))))
    (with-handlers ([exn:fail:mcp? (lambda (e)
                                    (define detail (hasheq 'code (exn:fail:mcp-code e) 'message (exn-message e)))
                                    (define body (hasheq 'jsonrpc "2.0" 'error (if (exn:fail:mcp-data e) (hash-set detail 'data (exn:fail:mcp-data e)) detail)))
                                    (json-response 400 (if (or (string? id) (rational? id)) (hash-set body 'id id) body)))]
                    [exn:fail? (lambda (_) (json-response 400 (hasheq 'jsonrpc "2.0" 'error (hasheq 'code -32700 'message "Invalid request body"))))])
      (define origin (get-header "Origin"))
      (cond [(and origin (not (member origin origins))) (json-response 403 #f)]
            [(not (bytes=? (request-method req) #"POST")) (json-response 405 #f (list (header #"Allow" #"POST")))]
            [else
             (define principal (authenticate headers))
             (cond [(not principal) (json-response 401 #f (list (header #"WWW-Authenticate" #"Bearer")))]
                   [else
                    (unless (regexp-match? #px"^application/json(?:;|$)" (or (get-header "Content-Type") "")) (mcp-error -32600 "Expected application/json"))
                    (define raw (or (request-post-data/raw req) #""))
                    (when (> (bytes-length raw) max-bytes) (mcp-error -32600 "Request body limit exceeded"))
                    (define message (string->json (bytes->string/utf-8 raw) #:max-bytes max-bytes))
                    (when (hash? message) (set! id (hash-ref message 'id missing)))
                    (unless (and (hash? message) (string? (hash-ref message 'method #f))) (mcp-error -32600 "Expected a JSON-RPC request or notification"))
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
                    (cond [(not (hash-has-key? message 'id)) (dispatch-message rt message #:principal principal) (json-response 202 #f)]
                          [(or sse? (equal? method "subscriptions/listen") (hash-has-key? (hash-ref params '_meta (hasheq)) 'progressToken))
                           (response/output
                            (lambda (out)
                              (define (send m) (when m (display "event: message\ndata: " out) (write-json m out) (display "\n\n" out) (flush-output out)))
                              (parameterize ([current-output-port (current-error-port)]) (send (dispatch-message rt message #:principal principal #:notify send))))
                            #:mime-type #"text/event-stream" #:headers (list (header #"Cache-Control" #"no-cache")))]
                          [else (define result (dispatch-message rt message #:principal principal))
                                (define code (hash-ref (hash-ref result 'error (hasheq)) 'code #f))
                                (json-response (cond [(equal? code -32601) 404] [(member code '(-32602 -32600 -32020 -32021 -32022)) 400] [else 200]) result)])])]))))
(define header-value/raw header-value)
(define (serve-http rt #:port [port 8000] #:host [host "127.0.0.1"] #:origins [origins #f]
                    #:authenticate [authenticate (lambda (_) 'local)] #:sse? [sse? #f] #:confirmation [confirmation #f])
  (serve #:dispatch (dispatch/servlet (make-http-handler rt #:origins (or origins (list (format "http://~a:~a" host port))) #:authenticate authenticate #:sse? sse?))
         #:port port #:listen-ip host #:confirmation-channel confirmation
         #:safety-limits (make-safety-limits #:max-request-body-length 1048576)))
(struct http-client (url token next-id lock schemas) #:mutable #:transparent)
(define (make-http-client url #:token [token #f] #:schemas [schemas (hash)]) (http-client (string->url url) token 0 (make-semaphore 1) (hash-copy schemas)))
(define (http-client-request client method [params (hasheq)] #:capabilities [caps (hasheq)])
  (define id (call-with-semaphore (http-client-lock client) (lambda () (set-http-client-next-id! client (add1 (http-client-next-id client))) (http-client-next-id client))))
  (define custodian (make-custodian))
  (define ready (make-semaphore 0)) (define result (box #f)) (define notices (make-async-channel 64))
  (define (finish! v)
    (define processed
      (if (and (equal? method "tools/list") (hash? v) (hash-has-key? v 'result))
          (let* ([body (hash-ref v 'result)]
                 [accepted (filter (lambda (tool) (with-handlers ([exn:fail? (lambda (_) #f)])
                                                    (header-bindings (hash-ref tool 'inputSchema))
                                                    (call-with-semaphore (http-client-lock client) (lambda () (hash-set! (http-client-schemas client) (hash-ref tool 'name) (hash-ref tool 'inputSchema)))) #t)) (hash-ref body 'tools '()))])
            (hash-set v 'result (hash-set body 'tools accepted))) v))
    (unless (sync/timeout 0 (semaphore-peek-evt ready)) (set-box! result processed) (semaphore-post ready)))
  (define handle (request-handle id ready result (lambda () (custodian-shutdown-all custodian) (finish! (exn:fail "Request cancelled" (current-continuation-marks)))) notices))
  (parameterize ([current-custodian custodian])
    (thread (lambda ()
              (with-handlers ([exn:fail? finish!])
                (define u (http-client-url client))
                (define ssl? (equal? (url-scheme u) "https"))
                (define relative (url->string (struct-copy url u [scheme #f] [user #f] [host #f] [port #f] [fragment #f])))
                (define target (if (string-prefix? relative "/") relative (string-append "/" relative)))
                (define-values (status headers in)
                  (http-sendrecv (url-host u) target
                                 #:ssl? ssl? #:port (or (url-port u) (if ssl? 443 80)) #:method "POST"
                                 #:headers (map (lambda (p) (string-append (car p) ": " (cdr p)))
                                                (append (request-headers method params)
                                                        (if (equal? method "tools/call")
                                                            (map (lambda (p) (cons (car p) (encode-header-value (cdr p))))
                                                                 (mirrored-headers (hash-ref (http-client-schemas client) (hash-ref params 'name) (hasheq)) (hash-ref params 'arguments (hasheq)))) '())
                                                        (if (http-client-token client) (list (cons "Authorization" (string-append "Bearer " (http-client-token client)))) '())))
                                 #:data (json->string (hasheq 'jsonrpc "2.0" 'id id 'method method 'params (hash-set params '_meta (request-meta #:capabilities caps #:extra (hash-ref params '_meta (hasheq))))))))
                (dynamic-wind void
                  (lambda ()
                    (if (ormap (lambda (h) (regexp-match? #rx#"(?i:content-type: text/event-stream)" h)) headers)
                        (let loop ([data '()])
                          (define line (read-line in 'any))
                          (cond [(eof-object? line) (error 'http-client "SSE closed before a response")]
                                [(equal? line "")
                                 (if (null? data) (loop '())
                                     (let ([m (string->json (string-join (reverse data) "\n"))])
                                       (if (hash-has-key? m 'id) (finish! m)
                                           (begin (unless (sync/timeout 0 (async-channel-put-evt notices m)) (error 'http-client "notification queue overflow")) (loop '())))))]
                                [(string-prefix? line "data:") (loop (cons (string-trim (substring line 5) #:left? #t #:right? #f) data))]
                                [else (loop data)]))
                        (finish! (string->json (port->string (make-limited-input-port in 1048577))))))
                  (lambda () (close-input-port in))))))) handle)
(define (http-client-call client method [params (hasheq)] #:capabilities [caps (hasheq)])
  (define v (sync (http-client-request client method params #:capabilities caps))) (if (exn? v) (raise v) v))
