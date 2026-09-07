#lang racket/base
(require rackunit racket/tcp racket/port racket/string mcp/http mcp/private/http-wire)
(define (response bytes proc #:close? [close? #t])
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner])
        (define listener (tcp-listen 0 4 #t "127.0.0.1"))
        (define-values (_ port _r _rp) (tcp-addresses listener #t))
        (thread (lambda ()
          (define-values (in out) (tcp-accept listener))
          (let loop () (define line (read-line in 'any)) (unless (equal? line "") (loop)))
          (write-bytes bytes out) (flush-output out)
          (if close? (close-output-port out) (sync never-evt))))
        (proc port)))
    (lambda () (custodian-shutdown-all owner))))
(define (body port [limit 65536])
  (define-values (_status _headers in) (bounded-http-sendrecv "127.0.0.1" "/" #:port port #:max-header-bytes limit))
  (dynamic-wind void (lambda () (port->bytes in)) (lambda () (close-input-port in))))
(check-equal? (response #"HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc" body) #"abc")
(check-equal? (response #"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 3, 3\r\n\r\nabc" body) #"abc")
(check-equal? (response #"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n2;name=value\r\nbc\r\n0\r\nX-Trailer: yes\r\n\r\n" body) #"abc")
(for ([wire (list #"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabc"
                  #"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Length: 4\r\n\r\nabc"
                  #"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 3\r\n\r\nabc"
                  #"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nabc"
                  #"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\naX\n"
                  #"HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\nabc"
                  #"HTTP/1.1 200 OK\r\n folded: bad\r\n\r\n")])
  (check-exn exn:fail? (lambda () (response wire body))))
(check-exn #rx"limit" (lambda () (response (bytes-append #"HTTP/1.1 200 OK\r\nX-Huge: " (make-bytes 200 65))
                                          (lambda (p) (body p 64)) #:close? #f)))
(check-exn #rx"limit" (lambda () (response (bytes-append #"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" (make-bytes 8193 65)) body #:close? #f)))
;; A legal large chunk must be processed incrementally. Waiting for the claimed
;; chunk to finish would stall this completed SSE response indefinitely.
(response #"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFFFFFF\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n"
  (lambda (p)
    (define value (sync/timeout 2 (http-client-request (make-http-client (format "http://127.0.0.1:~a/" p)) "server/discover")))
    (check-true (hash? value))) #:close? #f)
(check-exn exn:fail? (lambda () (make-http-client "ftp://localhost")))
(check-exn exn:fail? (lambda () (make-http-client "https://user:password@localhost")))
