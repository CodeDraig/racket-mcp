#lang racket/base
(require rackunit racket/port racket/async-channel net/http-client
         mcp mcp/http mcp/stdio)
(define rt (make-runtime (make-interface)))
(define good (hasheq 'jsonrpc "2.0" 'id 1 'method "server/discover" 'params (hasheq '_meta (request-meta))))
(define bads (list #f '() json-null 3 "request"
  (hash-set good 'id 1/2) (hash-set good 'id #f) (hash-set good 'id json-null)
  (hash-set good 'jsonrpc "1.0") (hash-set good 'method #f)
  (hash-set good 'params '()) (hash-set good 'result (hasheq))
  (hash-set good 'error (hasheq 'code -1 'message "error"))))
(define (check-rejection message result)
  (check-equal? (hash-ref (hash-ref result 'error) 'code) -32600)
  (define id (and (hash? message) (hash-ref message 'id #f)))
  (check-equal? (hash-has-key? result 'id) (and (or (string? id) (exact-integer? id)) #t)))
(for ([m (in-list bads)]) (check-rejection m (dispatch-message rt m)))
;; Bad input is rejected before it consumes a worker slot. JSON false is data,
;; not the parser's failure sentinel, and must receive an InvalidRequest error.
(define-values (server-in peer-out) (make-pipe))
(define-values (peer-in server-out) (make-pipe))
(define server (thread (lambda () (serve-stdio rt #:input server-in #:output server-out))))
(for ([m (in-list bads)])
  (write-json m peer-out) (newline peer-out) (flush-output peer-out)
  (check-not-false (sync/timeout 2 peer-in))
  (check-rejection m (string->json (read-json-line peer-in))))
(close-output-port peer-out)
(check-not-false (sync/timeout 2 (thread-dead-evt server)))
(close-input-port server-in) (close-output-port server-out) (close-input-port peer-in)

;; HTTP rejects the same envelopes before request-specific header checks or SSE.
(define confirmation (make-async-channel))
(define stop (serve-http rt #:port 0 #:confirmation confirmation))
(define port (sync/timeout 3 confirmation))
(dynamic-wind void
  (lambda ()
    (for ([m (in-list bads)])
      (define-values (status headers in)
        (http-sendrecv "127.0.0.1" "/mcp" #:port port #:method "POST"
          #:headers '("Content-Type: application/json" "Accept: application/json, text/event-stream")
          #:data (json->string m)))
      (check-regexp-match #rx#"400" status)
      (define result (string->json (port->string in)))
      (close-input-port in)
      (check-rejection m result)))
  stop)
(custodian-shutdown-all (runtime-custodian rt))

;; Cancellation-shaped messages must not reach cancel! through an invalid
;; envelope or malformed parameters. A ping acts as a reader-order barrier.
(define started (make-async-channel))
(define release (make-semaphore 0))
(define wait-runtime (make-runtime (make-interface #:tools
  (list (make-tool "wait" '() (lambda (_)
    (async-channel-put started (current-thread)) (sync release) (text-result "done")))))))
(define-values (wait-in writer) (make-pipe))
(define-values (reader wait-out) (make-pipe))
(define wait-server (thread (lambda () (serve-stdio wait-runtime #:input wait-in #:output wait-out))))
(define (send m) (write-json m writer) (newline writer) (flush-output writer))
(define (receive)
  (check-not-false (sync/timeout 2 reader))
  (string->json (read-json-line reader)))
(send (hasheq 'jsonrpc "2.0" 'id 2 'method "tools/call"
  'params (hasheq 'name "wait" 'arguments (hasheq) '_meta (request-meta))))
(define active (sync/timeout 2 started))
(check-true (thread? active))
(send (hasheq 'jsonrpc "1.0" 'method "notifications/cancelled" 'params (hasheq 'requestId 2)))
(check-equal? (hash-ref (hash-ref (receive) 'error) 'code) -32600)
(for ([params (list (hasheq 'requestId 2 'reason #f) (hasheq 'requestId 1/2) (hasheq))])
  (send (hasheq 'jsonrpc "2.0" 'method "notifications/cancelled" 'params params)))
(send (hash-set good 'id 3))
(check-equal? (hash-ref (receive) 'id) 3)
(check-false (thread-dead? active))
(semaphore-post release)
(check-equal? (hash-ref (receive) 'id) 2)
(close-output-port writer)
(check-not-false (sync/timeout 2 (thread-dead-evt wait-server)))
(close-input-port wait-in) (close-output-port wait-out) (close-input-port reader)
(custodian-shutdown-all (runtime-custodian wait-runtime))

;; Missing-resource diagnostics retain the requested identity per the resource
;; error contract, rather than making callers reconstruct it from log context.
(define missing-resource-runtime
  (make-runtime (make-interface #:resources (list (make-resource "present" "test:///present" (lambda () "yes"))))))
(define missing-resource-response
  (dispatch-message missing-resource-runtime
    (hasheq 'jsonrpc "2.0" 'id "missing" 'method "resources/read"
            'params (hasheq '_meta (request-meta) 'uri "test:///absent"))))
(check-equal? (hash-ref (hash-ref missing-resource-response 'error) 'data) (hasheq 'uri "test:///absent"))
(custodian-shutdown-all (runtime-custodian missing-resource-runtime))
