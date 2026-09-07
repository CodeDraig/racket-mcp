#lang racket/base
(require rackunit racket/tcp racket/port racket/string racket/async-channel net/http-client
         mcp mcp/http)
(define (with-response body proc)
  (define owner (make-custodian))
  (define closed (make-semaphore 0))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner])
        (define listener (tcp-listen 0 4 #t "127.0.0.1"))
        (define-values (_ port _r _rp) (tcp-addresses listener #t))
        (thread
         (lambda ()
           (define-values (in out) (tcp-accept listener))
           (let loop ([size 0])
             (define line (read-line in 'any))
             (cond [(equal? line "") (read-bytes size in)]
                   [(eof-object? line) (void)]
                   [else (define match (regexp-match #px"(?i:^content-length: *)([0-9]+)" line))
                         (loop (if match (string->number (cadr match)) size))]))
           (display "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n" out)
           (display body out) (flush-output out)
           ;; Keep the stream open so bounded-input tests cannot pass by EOF.
           ;; The client must close the socket after success or parser failure.
           (with-handlers ([exn:fail? (lambda (_) (semaphore-post closed))])
             (when (eof-object? (read-byte in)) (semaphore-post closed)))))
        (proc (format "http://127.0.0.1:~a/mcp" port))
        (check-not-false (sync/timeout 2 (semaphore-peek-evt closed)))))
    (lambda () (custodian-shutdown-all owner))))
(for ([body (list "data: {\"jsonrpc\":\"2.0\",\"id\":99,\"result\":{}}\n\n"
                  "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"elicitation/create\"}\n\n"
                  "data: []\n\n"
                  (string-append "data: " (make-string 130 #\x)))])
  (with-response body
    (lambda (url)
      (define result (sync/timeout 2 (http-client-request (make-http-client url #:max-response-bytes 128) "server/discover")))
      (check-true (exn:fail? result)))))
(with-response ": keep-alive\r\n\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\r\n\r\n"
  (lambda (url)
    (define result (sync/timeout 2 (http-client-request (make-http-client url) "server/discover")))
    (check-equal? result (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq)))))
;; A quiet handler still sends keep-alives; losing its output stream must stop
;; the request worker even if application code ignores cooperative cancellation.
(define started (make-async-channel))
(define rt (make-runtime (make-interface #:tools
  (list (make-tool "wait" '() (lambda (_) (async-channel-put started (current-thread)) (sync never-evt)))))))
(define confirmation (make-async-channel))
(define stop (serve-http rt #:port 0 #:sse? #t #:keepalive-seconds 0.02 #:confirmation confirmation))
(define port (sync/timeout 3 confirmation))
(define connection-owner (make-custodian))
(dynamic-wind void
  (lambda ()
    (define params (hasheq 'name "wait" 'arguments (hasheq) '_meta (request-meta)))
    (define-values (status headers in)
      (parameterize ([current-custodian connection-owner])
      (http-sendrecv "127.0.0.1" "/mcp" #:port port #:method "POST"
        #:headers (map (lambda (p) (string-append (car p) ": " (cdr p))) (request-headers "tools/call" params))
        #:data (json->string (hasheq 'jsonrpc "2.0" 'id 1 'method "tools/call" 'params params)))))
    (check-not-false (ormap (lambda (h) (regexp-match? #rx#"(?i:x-accel-buffering: no)" h)) headers))
    (check-equal? (read-line in) ": keep-alive")
    (define worker (sync/timeout 2 started))
    (check-true (thread? worker))
    (close-input-port in)
    (custodian-shutdown-all connection-owner)
    (check-not-false (sync/timeout 3 (thread-dead-evt worker))))
  (lambda () (custodian-shutdown-all connection-owner) (stop) (custodian-shutdown-all (runtime-custodian rt))))

;; A request-scoped stream cannot report another operation's progress, and
;; repeated/decreasing values fail even when followed by a valid final response.
(for ([body (list
             "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":\"foreign\",\"progress\":1}}\n\n"
             "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":0,\"progress\":1}}\n\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":0,\"progress\":1}}\n\n")])
  (with-response body
    (lambda (url)
      (define h (http-client-request (make-http-client url) "ping" (hasheq '_meta (hasheq 'progressToken 0))))
      (check-true (exn:fail? (sync/timeout 2 h))))))

(for ([method '("subscriptions/listen" "ping")])
  (with-response "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":1}}\n\n"
    (lambda (url)
      (define result (sync/timeout 2 (http-client-request (make-http-client url) method)))
      (if (equal? method "subscriptions/listen")
          (check-equal? result (hasheq 'jsonrpc "2.0" 'method "notifications/cancelled" 'params (hasheq 'requestId 1)))
          (check-true (exn:fail? result))))))
