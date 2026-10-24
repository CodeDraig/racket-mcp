#lang racket/base
(require "../json.rkt" "../runtime.rkt" "../subscription.rkt" "request-message.rkt")
(provide serve-stdio)
(define (serve-stdio rt #:input [in (current-input-port)] #:output [out (current-output-port)] #:workers [limit 32] #:principal [principal 'local])
  (define lock (make-semaphore 1))
  (define slots (make-semaphore limit))
  (define running (make-hash))
  (define guard (make-semaphore 1))
  (define owner (make-custodian))
  (define serving-thread (current-thread))
  (define accepting? #t)
  (define output-failure (box #f))
  (define (send message)
    (when message
      (call-with-semaphore lock
        (lambda ()
          (unless (unbox output-failure)
            (with-handlers ([(lambda (_) #t)
                            (lambda (failure)
                              (set-box! output-failure (cons #t failure))
                              (cond [(eq? (current-thread) serving-thread) (raise failure)]
                                    [accepting? (break-thread serving-thread)]))])
              (write-json message out) (newline out) (flush-output out)))))))
  (define (reject id code message)
    (send (hash-set (hasheq 'jsonrpc "2.0" 'error (hasheq 'code code 'message message)) 'id id)))
  (define (cancel! id)
    (define entry (call-with-semaphore guard (lambda () (hash-ref running id #f))))
    (when entry
      (semaphore-post (vector-ref entry 1))
      (parameterize ([current-custodian owner])
        (thread (lambda () (sync (alarm-evt (+ (current-inexact-milliseconds) 200))) (custodian-shutdown-all (vector-ref entry 0)))))))
  (with-handlers ([exn:break? (lambda (failure)
                              (raise (if (unbox output-failure) (cdr (unbox output-failure)) failure)))])
  (dynamic-wind void
    (lambda ()
      (let loop ()
        (define line (read-json-line in))
        (unless (eof-object? line)
          (define parsed (with-handlers ([exn:fail? (lambda (_) (send (hasheq 'jsonrpc "2.0" 'error (hasheq 'code -32700 'message "Parse error"))) missing)]) (string->json line)))
          (define message
            (if (missing? parsed) missing
                (with-handlers ([exn:fail? (lambda (_) (send (dispatch-message rt parsed #:principal principal)) missing)])
                  (check-client-message parsed)
                  parsed)))
          (unless (missing? message)
            (define id (and (hash? message) (hash-ref message 'id missing)))
            (cond
              [(and (hash? message) (equal? (hash-ref message 'method #f) "notifications/cancelled") (missing? id))
               (define params (hash-ref message 'params (hasheq)))
               (with-handlers ([exn:fail? void])
                 (check-cancellation-params params)
                 (cancel! (hash-ref params 'requestId)))]
              [(missing? id) (dispatch-message rt message #:principal principal)]
              [(not (semaphore-try-wait? slots)) (reject id -32000 "Concurrent request limit exceeded")]
              [else
               (define child (make-custodian owner))
               (define cancelled (make-semaphore 0))
               (define entry (vector child cancelled #f))
               (define responded? (box #f))
               (define duplicate? (call-with-semaphore guard (lambda () (if (hash-has-key? running id) #t (begin (hash-set! running id entry) #f)))))
               (if duplicate? (begin (reject id -32600 "Duplicate active request ID") (semaphore-post slots) (custodian-shutdown-all child))
                   (let ([worker
                          (parameterize ([current-custodian child])
                            (thread (lambda ()
                              (parameterize ([current-output-port (current-error-port)]
                                             [current-cancellation-event (semaphore-peek-evt cancelled)]
                                             [current-cancelled? (lambda () (and (sync/timeout 0 (semaphore-peek-evt cancelled)) #t))])
                                (define result (dispatch-message rt message #:principal principal #:notify send))
                                (when (or (not ((current-cancelled?))) (equal? (hash-ref message 'method #f) "subscriptions/listen"))
                                  (send result) (set-box! responded? #t))))))])
                     (vector-set! entry 2 worker)
                     (parameterize ([current-custodian owner])
                       (thread (lambda ()
                         (thread-wait worker)
                         (when (and (sync/timeout 0 (semaphore-peek-evt cancelled)) (not (unbox responded?))
                                    (equal? (hash-ref message 'method) "subscriptions/listen"))
                           (send (hasheq 'jsonrpc "2.0" 'id id 'result
                                         (hasheq 'resultType "complete" '_meta (hasheq 'io.modelcontextprotocol/subscriptionId id)))))
                         (call-with-semaphore guard (lambda () (hash-remove! running id)))
                         (semaphore-post slots)
                         (custodian-shutdown-all child))))))]))
          (loop)))
      (void))
    (lambda ()
      (parameterize-break #f
      (set! accepting? #f)
      (close-subscriptions! (runtime-subscriptions rt))
      (define active (call-with-semaphore guard (lambda () (hash-values running))))
      (for ([entry (in-list active)]) (semaphore-post (vector-ref entry 1)))
      ;; One shared grace period, not a separate timeout per request. Task workers
      ;; are owned by the runtime and are deliberately outside this custodian.
      (define deadline (alarm-evt (+ (current-inexact-milliseconds) 200)))
      (for ([entry (in-list active)] #:when (thread? (vector-ref entry 2)))
        (sync deadline (thread-dead-evt (vector-ref entry 2))))
      (custodian-shutdown-all owner))))
    (when (unbox output-failure) (raise (cdr (unbox output-failure))))))
