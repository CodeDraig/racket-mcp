#lang racket/base
(require racket/async-channel "../runtime.rkt" "../json.rkt" "../subscription.rkt")
(provide call-with-http-request-scope current-http-request-custodian start-http-request http-request-next stop-http-request!
         write-http-request (struct-out http-event))

;; A servlet's custodian can outlive its connection. serve-http supplies the
;; connection custodian so a failed header write also reaps an already-started
;; request whose response body callback never runs.
(define current-http-request-custodian (make-parameter #f))
(define current-request-scope (make-parameter #f))
(define (call-with-http-request-scope thunk)
  (define requests (box '()))
  (dynamic-wind void
    (lambda () (parameterize ([current-request-scope requests]) (thunk)))
    (lambda ()
      (parameterize-break #f
        (for ([request (in-list (unbox requests))]) (stop-http-request! request))))))
(struct http-request (owner cancelled events worker))
(struct http-event (kind value bytes) #:transparent)
(define (start-http-request rt message principal limit)
  (define owner (make-custodian (or (current-http-request-custodian) (current-custodian))))
  (define cancelled (make-semaphore 0))
  (define events (make-async-channel 64))
  (define (enqueue kind value)
    (define bytes (and value (string->bytes/utf-8 (json->string value))))
    (when (and bytes (> (bytes-length bytes) limit)) (error 'http-server "Response byte limit exceeded"))
    (async-channel-put events (http-event kind value bytes)))
  (define worker
    (parameterize ([current-custodian owner])
      (thread
        (lambda ()
          (with-handlers ([(lambda (_) #t)
                           (lambda (failure) (async-channel-put events (http-event 'failure failure #f)))])
            (parameterize ([current-output-port (current-error-port)]
                           [current-cancellation-event (semaphore-peek-evt cancelled)]
                           [current-cancelled? (lambda () (and (sync/timeout 0 (semaphore-peek-evt cancelled)) #t))])
              (enqueue 'done (dispatch-message rt message #:principal principal
                             #:notify (lambda (value) (when value (enqueue 'message value)))))))))))
  (define request (http-request owner cancelled events worker))
  (when (current-request-scope)
    (set-box! (current-request-scope) (cons request (unbox (current-request-scope)))))
  request)
(define (http-request-next request timeout)
  (sync/timeout timeout (http-request-events request)
    (wrap-evt (thread-dead-evt (http-request-worker request))
      (lambda (_)
        (or (sync/timeout 0 (http-request-events request))
            (http-event 'failure (exn:fail "HTTP request worker exited without a response" (current-continuation-marks)) #f))))))
(define (stop-http-request! request)
  (semaphore-post (http-request-cancelled request))
  (sync/timeout 0.2 (thread-dead-evt (http-request-worker request)))
  (custodian-shutdown-all (http-request-owner request)))
(define (write-http-request request out keepalive [first #f])
  (dynamic-wind void
    (lambda ()
      (let loop ([event first])
        (cond [(not event) (display ": keep-alive\n\n" out) (flush-output out)]
              [(eq? (http-event-kind event) 'failure) (raise (http-event-value event))]
              [(http-event-bytes event)
               (display "event: message\ndata: " out)
               (write-bytes (http-event-bytes event) out)
               (display "\n\n" out) (flush-output out)])
        (unless (and event (eq? (http-event-kind event) 'done))
          (loop (http-request-next request keepalive)))))
    (lambda () (stop-http-request! request))))
