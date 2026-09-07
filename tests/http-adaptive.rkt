#lang racket/base
(require rackunit racket/async-channel racket/port racket/tcp racket/string
         mcp mcp/http mcp/stdio mcp/subscription mcp/private/http-wire mcp/private/http-request)
(define started (make-async-channel))
(define released (make-semaphore 0))
(define cooperative (make-semaphore 0))
(define calls 0)
(tool (fast) (text-result "fast"))
(tool (slow [mode String])
  (set! calls (add1 calls))
  (async-channel-put started (current-thread))
  (cond [(equal? mode "cooperate") (sync (current-cancellation-event)) (semaphore-post cooperative)]
        [else (sync released)])
  (text-result "slow"))
(define rt (make-runtime (make-interface #:tools (list fast slow))))
(define confirmation (make-async-channel))
(define stop (serve-http rt #:port 0 #:confirmation confirmation #:keepalive-seconds 0.02 #:stream-after 0.1))
(define port (sync/timeout 5 confirmation))
(when (exn? port) (raise port))
(define params (hasheq 'name "slow" 'arguments (hasheq 'mode "wait") '_meta (request-meta)))
(define (request-wire params)
  (json->string (hasheq 'jsonrpc "2.0" 'id 1 'method "tools/call" 'params params)))
(define (headers params)
  (map (lambda (entry) (string-append (car entry) ": " (cdr entry))) (request-headers "tools/call" params)))
(define (content-type headers)
  (for/first ([h headers] #:when (regexp-match? #px#"(?i:^Content-Type:)" h)) h))
(dynamic-wind void
  (lambda ()
    ;; A port selected by the listener, rather than the configured zero, defines
    ;; the default allowed origin. Caller-provided allowlists remain authoritative.
    (define fast-params (hash-set* params 'name "fast" 'arguments (hasheq)))
    (define (check-origin target-port origin expected)
      (define-values (status _headers response)
        (bounded-http-sendrecv "127.0.0.1" "/mcp" #:port target-port #:method "POST"
          #:headers (cons (string-append "Origin: " origin) (headers fast-params))
          #:data (request-wire fast-params)))
      (dynamic-wind void
        (lambda () (check-regexp-match expected status) (port->bytes response))
        (lambda () (close-input-port response))))
    (check-origin port (format "http://127.0.0.1:~a" port) #rx#"200 OK")
    (check-origin port "http://127.0.0.1:0" #rx#"403")
    (check-origin port "http://evil.example.com" #rx#"403")
    (define explicit-ready (make-async-channel))
    (define explicit-stop
      (serve-http rt #:port 0 #:confirmation explicit-ready #:origins '("https://allowed.example")))
    (dynamic-wind void
      (lambda ()
        (define explicit-port (sync/timeout 5 explicit-ready))
        (when (exn? explicit-port) (raise explicit-port))
        (check-origin explicit-port "https://allowed.example" #rx#"200 OK")
        (check-origin explicit-port (format "http://127.0.0.1:~a" explicit-port) #rx#"403"))
      explicit-stop)
    (define-values (_status fast-headers fast-body)
      (bounded-http-sendrecv "127.0.0.1" "/mcp" #:port port #:method "POST"
        #:headers (headers (hash-set* params 'name "fast" 'arguments (hasheq))) #:data (request-wire (hash-set* params 'name "fast" 'arguments (hasheq)))))
    (check-regexp-match #rx#"application/json" (content-type fast-headers))
    (check-regexp-match #rx#"200 OK" _status)
    (check-equal? (hash-ref (hash-ref (read-json fast-body) 'result) 'content) (list (text-content "fast")))
    (close-input-port fast-body)
    ;; Headers become available while the handler is still waiting. Releasing
    ;; it completes the same request and executes the handler only once.
    (define-values (_slow-status slow-headers body)
      (bounded-http-sendrecv "127.0.0.1" "/mcp" #:port port #:method "POST" #:headers (headers params) #:data (request-wire params)))
    (check-regexp-match #rx#"text/event-stream" (content-type slow-headers))
    (define worker (sync/timeout 2 started))
    (check-true (thread? worker))
    (check-equal? calls 1)
    (semaphore-post released)
    (define text (port->string body))
    (close-input-port body)
    (check-regexp-match #rx"event: message" text)
    (check-regexp-match #rx"slow" text)
    (check-equal? calls 1)
    ;; Client cancellation reaches both cooperative and uncooperative workers.
    (define client (make-http-client (format "http://127.0.0.1:~a/mcp" port)))
    (for ([mode '("cooperate" "wait")])
      (define request (http-client-request client "tools/call" (hasheq 'name "slow" 'arguments (hasheq 'mode mode))))
      (define worker (sync/timeout 2 started))
      ;; Wait until the JSON selection window has elapsed, then close the stream.
      (sync (alarm-evt (+ (current-inexact-milliseconds) 150)))
      (request-cancel! request)
      (check-true (exn:fail:request-cancelled? (sync request)))
      (when (equal? mode "cooperate") (check-not-false (sync/timeout 2 cooperative)))
      (check-not-false (sync/timeout 2 worker)))
    ;; A TCP write half-close still permits a response. EOF is not cancellation.
    (define-values (in out) (tcp-connect "127.0.0.1" port))
    (define data (request-wire params))
    (fprintf out "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:~a\r\nConnection: close\r\nContent-Length: ~a\r\n" port (bytes-length (string->bytes/utf-8 data)))
    (for ([h (headers params)]) (fprintf out "~a\r\n" h))
    (display "\r\n" out) (display data out) (flush-output out)
    (close-output-port out)
    (define half-worker (sync/timeout 2 started))
    (check-true (thread? half-worker))
    (check-not-false (sync/timeout 2 in))
    (check-regexp-match #rx"200 OK" (read-line in 'any))
    (check-false (thread-dead? half-worker))
    (semaphore-post released)
    (define reply (port->string in))
    (close-input-port in)
    (check-regexp-match #rx"slow" reply)
    ;; A response-delivery error before the body writer runs still signals and
    ;; reaps the worker. This tests the dispatcher scope independently of I/O.
    (check-exn #rx"before body"
      (lambda ()
        (call-with-http-request-scope
          (lambda ()
            (start-http-request rt
              (hasheq 'jsonrpc "2.0" 'id 7 'method "tools/call"
                      'params (hash-set params 'arguments (hasheq 'mode "cooperate"))) "alice" 1048576)
            (check-true (thread? (sync/timeout 2 started)))
            (error 'delivery "before body")))))
    (check-not-false (sync/timeout 2 cooperative)))
  (lambda () (stop) (custodian-shutdown-all (runtime-custodian rt))))
