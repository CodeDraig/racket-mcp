#lang racket/base
(require racket/list racket/port racket/string net/url
         mcp/authorization mcp/http mcp/json mcp/oauth mcp/oauth-http mcp/oauth-http-client
         mcp/private/http-wire)
;; The pinned fixture grants authorization immediately and redirects to the
;; supplied callback. This development callback reads that redirect without
;; navigating to it; production applications supply their own browser integration.
(define args (current-command-line-arguments))
(define resource (vector-ref args (sub1 (vector-length args))))
(define context (let ([value (getenv "MCP_CONFORMANCE_CONTEXT")])
                  (if value (string->json value) (hasheq))))
(define redirect "http://localhost:3080/callback")
(define metadata-url
  (or (getenv "MCP_CONFORMANCE_CLIENT_METADATA_URL")
      "https://conformance-test.local/client-metadata.json"))
(define (browse address)
  (define u (string->url address))
  (unless (and (equal? (url-scheme u) "http")
               (member (url-host u) '("localhost" "127.0.0.1" "::1")))
    (error 'conformance-browser "expected a local harness authorization endpoint"))
  (define target (url->string (struct-copy url u [scheme #f] [host #f] [port #f])))
  (define-values (status headers in)
    (bounded-http-sendrecv (url-host u) target #:port (url-port u) #:method "GET"))
  (close-input-port in)
  (unless (regexp-match? #px#"^HTTP/[0-9.]+ 302 " status)
    (error 'conformance-browser "expected an authorization redirect"))
  (define locations
    (for/list ([header headers]
               #:do [(define m (regexp-match #px#"(?i:^location:)[\t ]*(.*)$" header))]
               #:when m) (bytes->string/utf-8 (cadr m))))
  (unless (= (length locations) 1) (error 'conformance-browser "expected one callback location"))
  (define callback (string->url (car locations)))
  (unless (equal? (url->string (struct-copy url callback [query '()] [fragment #f])) redirect)
    (error 'conformance-browser "callback URI mismatch"))
  (for/fold ([fields (hasheq)]) ([pair (url-query callback)])
    (when (hash-has-key? fields (car pair)) (error 'conformance-browser "duplicate callback parameter"))
    (hash-set fields (car pair) (cdr pair))))
(define issuer (hash-ref context 'issuer #f))
(define client-id (hash-ref context 'client_id #f))
(define secret (hash-ref context 'client_secret #f))
(define authorizer
  (make-oauth-authorizer #:resource resource #:redirect-uri redirect #:browse browse
    #:allow-loopback-http? #t
    #:pre-registered (if (and issuer client-id)
                        (hash issuer (oauth-registration issuer client-id redirect resource '())) (hash))
    #:client-authentication (if secret
        (hash issuer (oauth-client-authentication issuer client-id 'client_secret_basic secret)) (hash))
    #:client-metadata-url metadata-url
    #:client-metadata (client-id-metadata-document metadata-url "Racket MCP conformance" (list redirect))))
(define client (make-http-client resource))
(define (call method [params (hasheq)])
  (define response
    (with-handlers ([exn:fail:http:authorization?
                     (lambda (failure)
                       (authorize-http-client! client authorizer #:failure failure)
                       (http-client-call client method params))])
      (http-client-call client method params)))
  (when (hash-has-key? response 'error) (error 'conformance-client "MCP request failed: ~a" response))
  (hash-ref response 'result))
(void (call "server/discover"))
(define tools (hash-ref (call "tools/list") 'tools))
(define (default-argument schema)
  (case (string->symbol (hash-ref schema 'type "string"))
    [(integer number) 1] [(boolean) #t] [else "test"]))
(for ([tool tools])
  (define arguments
    (for/hasheq ([(key schema) (in-hash (hash-ref (hash-ref tool 'inputSchema) 'properties (hasheq)))])
      (values key (hash-ref schema 'default (lambda () (default-argument schema))))))
  (void (call "tools/call" (hasheq 'name (hash-ref tool 'name) 'arguments arguments))))
