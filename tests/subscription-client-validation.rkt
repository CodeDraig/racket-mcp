#lang racket/base
(require rackunit racket/tcp racket/async-channel mcp/http mcp/stdio mcp/json)

(define filter (hasheq 'toolsListChanged #t 'resourceSubscriptions '("file:///accepted")))
(define (notice id method [extra (hasheq)])
  (hasheq 'jsonrpc "2.0" 'method method
          'params (hash-set extra '_meta (hasheq 'io.modelcontextprotocol/subscriptionId id))))
(define (ack id [accepted filter])
  (notice id "notifications/subscriptions/acknowledged" (hasheq 'notifications accepted)))
(define (change id) (notice id "notifications/tools/list_changed"))
(define (run-peer transport method messages check)
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner])
        (define-values (h send)
          (case transport
            [(stdio)
             (define-values (in peer-out) (make-pipe))
             (define-values (peer-in out) (make-pipe))
             (define client (make-stdio-client in out))
             (define handle (client-request client method (hasheq 'notifications filter)))
             (read-json-line peer-in)
             (values handle (lambda (m) (write-json m peer-out) (newline peer-out) (flush-output peer-out)))]
            [(http)
             (define listener (tcp-listen 0 4 #t "127.0.0.1"))
             (define-values (_ port _r _rp) (tcp-addresses listener #t))
             (define handle (http-client-request (make-http-client (format "http://127.0.0.1:~a/" port))
                                                 method (hasheq 'notifications filter)))
             (define-values (in out) (tcp-accept listener))
             (let loop () (unless (equal? (read-line in 'any) "") (loop)))
             (display "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n" out)
             (flush-output out)
             (values handle (lambda (m) (display "data: " out) (write-json m out) (display "\n\n" out) (flush-output out)))]))
        (for ([m (in-list (messages (request-handle-id h)))]) (send m))
        (check h)))
    (lambda () (custodian-shutdown-all owner))))

(for ([transport '(stdio http)])
  (for ([messages (in-list
                   (list
                    (lambda (id) (list (change id)))
                    (lambda (id) (list (hasheq 'jsonrpc "2.0" 'method "notifications/tools/list_changed" 'params (hasheq 'requestId id))))
                    (lambda (id) (list (ack id) (ack id)))
                    (lambda (id) (list (ack id (hasheq 'promptsListChanged #t))))
                    (lambda (id) (list (ack id (hasheq 'toolsListChanged "yes"))))
                    (lambda (id) (list (ack id (hasheq 'resourceSubscriptions '("file:///foreign")))))
                    (lambda (id) (list (ack id (hasheq)) (change id)))
                    (lambda (id) (list (ack id) (notice id "notifications/resources/updated" (hasheq 'uri "file:///foreign"))))))])
    (test-case (format "~a rejects invalid subscription sequence" transport)
      (run-peer transport "subscriptions/listen" messages
                (lambda (h) (check-true (exn:fail? (sync/timeout 2 h)))))))
  (test-case (format "~a rejects subscription traffic on ordinary request" transport)
    (run-peer transport "ping" (lambda (id) (list (ack id)))
              (lambda (h) (check-true (exn:fail? (sync/timeout 2 h))))))
  (test-case (format "~a accepts partial filter then matching changes" transport)
    (run-peer transport "subscriptions/listen"
              (lambda (id) (list (ack id (hasheq 'toolsListChanged #t)) (change id)))
              (lambda (h)
                (check-equal? (sync/timeout 2 (request-handle-notifications h)) (ack (request-handle-id h) (hasheq 'toolsListChanged #t)))
                (check-equal? (sync/timeout 2 (request-handle-notifications h)) (change (request-handle-id h)))
                (check-false (sync/timeout 0 h))))))
(test-case "HTTP rejects another subscription's ID"
  (run-peer 'http "subscriptions/listen" (lambda (id) (list (ack (add1 id))))
            (lambda (h) (check-true (exn:fail? (sync/timeout 2 h))))))

;; Snapshot the filter at construction, not when a peer acknowledges it.
(require mcp/private/subscription-client)
(test-case "filter snapshot is independent of caller mutation"
  (define requested (make-hasheq (list (cons 'toolsListChanged #t))))
  (define tracker (make-subscription-tracker 1 "subscriptions/listen" (hasheq 'notifications requested)))
  (hash-set! requested 'promptsListChanged #t)
  (check-exn #rx"subset" (lambda () (observe-subscription! tracker "notifications/subscriptions/acknowledged"
                                       (hash-ref (ack 1 (hasheq 'promptsListChanged #t)) 'params))))
  (observe-subscription! tracker "notifications/subscriptions/acknowledged"
                         (hash-ref (ack 1 (hasheq 'toolsListChanged #t)) 'params)))
(test-case "delivered acknowledgement cannot mutate retained URI acceptance"
  (define uri (string-copy "file:///accepted"))
  (define accepted (hasheq 'resourceSubscriptions (list uri)))
  (define tracker (make-subscription-tracker 1 "subscriptions/listen" (hasheq 'notifications accepted)))
  (observe-subscription! tracker "notifications/subscriptions/acknowledged" (hash-ref (ack 1 accepted) 'params))
  (string-set! uri 8 #\X)
  (check-exn #rx"outside" (lambda () (observe-subscription! tracker "notifications/resources/updated"
                                          (hash-ref (notice 1 "notifications/resources/updated" (hasheq 'uri uri)) 'params))))
  (check-not-exn (lambda () (observe-subscription! tracker "notifications/resources/updated"
                                                  (hash-ref (notice 1 "notifications/resources/updated" (hasheq 'uri "file:///accepted")) 'params)))))
