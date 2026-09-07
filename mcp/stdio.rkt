#lang racket/base
(require racket/async-channel racket/port "json.rkt" "runtime.rkt" "subscription.rkt" "private/wire-message.rkt" "private/request-message.rkt" "private/progress.rkt")
(provide serve-stdio make-stdio-client client-request client-call client-close!
         (struct-out request-handle) (struct-out exn:fail:notification-overflow) (struct-out exn:fail:request-cancelled) (struct-out exn:fail:request-timeout) request-cancel!)
(struct request-handle (id ready result cancel notifications) #:transparent
  #:property prop:evt (lambda (self) (wrap-evt (semaphore-peek-evt (request-handle-ready self))
                                             (lambda (_) (unbox (request-handle-result self))))))
(define (request-cancel! handle) ((request-handle-cancel handle)))
(define (serve-stdio rt #:input [in (current-input-port)] #:output [out (current-output-port)] #:workers [limit 32])
  (define lock (make-semaphore 1))
  (define slots (make-semaphore limit))
  (define running (make-hash))
  (define guard (make-semaphore 1))
  (define owner (make-custodian))
  (define (send message) (when message (call-with-semaphore lock (lambda () (write-json message out) (newline out) (flush-output out)))))
  (define (reject id code message)
    (send (hash-set (hasheq 'jsonrpc "2.0" 'error (hasheq 'code code 'message message)) 'id id)))
  (define (cancel! id)
    (define entry (call-with-semaphore guard (lambda () (hash-ref running id #f))))
    (when entry
      (semaphore-post (vector-ref entry 1))
      (parameterize ([current-custodian owner])
        (thread (lambda () (sync (alarm-evt (+ (current-inexact-milliseconds) 200))) (custodian-shutdown-all (vector-ref entry 0)))))))
  (dynamic-wind void
    (lambda ()
      (let loop ()
        (define line (read-json-line in))
        (unless (eof-object? line)
          (define parsed (with-handlers ([exn:fail? (lambda (_) (send (hasheq 'jsonrpc "2.0" 'error (hasheq 'code -32700 'message "Parse error"))) missing)]) (string->json line)))
          (define message
            (if (missing? parsed) missing
                (with-handlers ([exn:fail? (lambda (_) (send (dispatch-message rt parsed)) missing)])
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
              [(missing? id) (dispatch-message rt message)]
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
                                (define result (dispatch-message rt message #:notify send))
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
      (close-subscriptions! (runtime-subscriptions rt))
      (define active (call-with-semaphore guard (lambda () (hash-values running))))
      (for ([entry (in-list active)]) (semaphore-post (vector-ref entry 1)))
      ;; One shared grace period, not a separate timeout per request. Task workers
      ;; are owned by the runtime and are deliberately outside this custodian.
      (define deadline (alarm-evt (+ (current-inexact-milliseconds) 200)))
      (for ([entry (in-list active)] #:when (thread? (vector-ref entry 2)))
        (sync deadline (thread-dead-evt (vector-ref entry 2))))
      (custodian-shutdown-all owner))))
(struct exn:fail:request-timeout exn:fail (request-id seconds) #:transparent)
(struct exn:fail:request-cancelled exn:fail (request-id) #:transparent)
(struct exn:fail:notification-overflow exn:fail (request-id) #:transparent)
(struct stdio-client (in out pending tokens lock writer-lock reader next-id closed? close-ports?
                         control control-worker notification-limit request-limit progress-token-limit timeout) #:mutable)
(struct pending-request (handle token capabilities progress method outbound) #:transparent)
(struct outbound-request (id wire state) #:transparent)
(struct outbound-cancel (request) #:transparent)
(define (check-timeout v)
  (unless (or (not v) (and (rational? v) (positive? v)))
    (raise-argument-error 'stdio-client "positive finite timeout or #f" v)))
(define (make-stdio-client in out #:close-ports? [close-ports? #t]
                           #:notification-limit [notification-limit 64]
                           #:request-limit [request-limit 1024] #:progress-token-limit [token-limit 1024]
                           #:timeout [timeout 30] #:outbound-limit [outbound-limit 64])
  (unless (exact-positive-integer? notification-limit)
    (raise-argument-error 'make-stdio-client "exact-positive-integer?" notification-limit))
  (for ([limit (in-list (list request-limit token-limit outbound-limit))])
    (unless (exact-positive-integer? limit) (raise-argument-error 'make-stdio-client "exact-positive-integer?" limit)))
  (check-timeout timeout)
  (define c (stdio-client in out (make-hash) (make-hash) (make-semaphore 1)
                          (make-semaphore 1) #f 0 #f close-ports? (make-async-channel outbound-limit) #f notification-limit request-limit token-limit timeout))
  ;; The gate prevents EOF cleanup racing installation of the reader field.
  (define start (make-semaphore 0))
  (define reader
    (thread
     (lambda ()
       (semaphore-wait start)
       (with-handlers ([exn:fail? (lambda (e) (client-close! c e))])
         (let loop ()
           (define line (read-json-line in))
           (if (eof-object? line)
               (client-close! c (exn:fail "Transport closed" (current-continuation-marks)))
               (begin (client-receive! c (string->json line)) (loop))))))))
  (define control-worker
    (thread
     (lambda ()
       (semaphore-wait start)
       (with-handlers ([exn:fail? (lambda (e) (client-close! c e))])
         (let loop ()
           (write-outbound! c (async-channel-get (stdio-client-control c)))
           (loop))))))
  (set-stdio-client-reader! c reader)
  (set-stdio-client-control-worker! c control-worker)
  (semaphore-post start)
  (semaphore-post start)
  c)
;; Called under the state lock. Completion releases a progress token for reuse.
(define (finish-request! c id value #:release-token? [release-token? #t])
  (define pending (hash-ref (stdio-client-pending c) id #f))
  (when release-token?
    (if pending
        (unless (missing? (pending-request-token pending))
          (hash-remove! (stdio-client-tokens c) (pending-request-token pending)))
        ;; Locally overflowed requests retain their token until the remote end
        ;; acknowledges termination, preventing late progress from being reused.
        (for ([token (in-list (hash-keys (stdio-client-tokens c)))]
              #:when (equal? id (hash-ref (stdio-client-tokens c) token)))
          (hash-remove! (stdio-client-tokens c) token))))
  (when pending
    (hash-remove! (stdio-client-pending c) id)
    (define h (pending-request-handle pending))
    (set-box! (request-handle-result h) value)
    (semaphore-post (request-handle-ready h))))
(define (client-receive! c m)
  (define kind (check-server-message m))
  (when (eq? kind 'uncorrelated-error)
    (error 'client "Received an error without a correlatable request ID: ~e" (hash-ref m 'error)))
  (define id (hash-ref m 'id missing))
  (define method (hash-ref m 'method missing))
  (define response? (eq? kind 'response))
  (call-with-semaphore
   (stdio-client-lock c)
   (lambda ()
     (cond
       [response?
        (define pending (hash-ref (stdio-client-pending c) id #f))
        (when pending (check-result-capabilities! m (pending-request-capabilities pending)))
        (finish-request! c id m)]
       [else
        (define params (hash-ref m 'params (hasheq)))
        (define meta (hash-ref params '_meta (hasheq)))
        (unless (hash? meta) (error 'client "invalid notification metadata"))
        (define target-id
          (if (equal? method "notifications/progress")
              (hash-ref (stdio-client-tokens c) (hash-ref params 'progressToken missing) missing)
              (if (equal? method "notifications/cancelled")
                  (hash-ref params 'requestId missing)
                  (hash-ref meta 'io.modelcontextprotocol/subscriptionId
                            (hash-ref params 'requestId missing)))))
        (define pending (hash-ref (stdio-client-pending c) target-id #f))
        (when (and pending (equal? method "notifications/progress"))
          (observe-progress! (pending-request-progress pending) params))
        (if (equal? method "notifications/cancelled")
            (begin
              (check-cancellation-params params)
              (when (and (hash-has-key? meta 'io.modelcontextprotocol/subscriptionId)
                         (not (equal? (hash-ref meta 'io.modelcontextprotocol/subscriptionId) target-id)))
                (error 'client "Conflicting subscription cancellation IDs"))
              (when pending
                (unless (equal? (pending-request-method pending) "subscriptions/listen")
                  (error 'client "Server cancellation may only close a subscription"))
                (finish-request! c target-id m)))
            (when pending
              (unless (sync/timeout 0 (async-channel-put-evt
                                      (request-handle-notifications (pending-request-handle pending)) m))
                (finish-request! c target-id
                  (exn:fail:notification-overflow
                   "Notification queue overflow; re-listen and refresh cached data"
                   (current-continuation-marks) target-id)
                  #:release-token? #f)
                ;; The reader must continue draining other requests even if the
                ;; peer is temporarily not consuming cancellation notifications.
                (unless (sync/timeout 0
                          (async-channel-put-evt (stdio-client-control c)
                            (outbound-cancel (pending-request-outbound pending))))
                  (error 'client "outbound cancellation queue exhausted")))))]))))
(define (cancel-request! c id [reason (exn:fail:request-cancelled "Request cancelled locally" (current-continuation-marks) id)])
  (with-handlers ([exn:fail? (lambda (e) (client-close! c e))])
    (call-with-semaphore (stdio-client-lock c)
      (lambda ()
        (define pending (hash-ref (stdio-client-pending c) id #f))
        (when pending
          (define outbound (pending-request-outbound pending))
          (finish-request! c id reason
            #:release-token? (eq? (unbox (outbound-request-state outbound)) 'queued))
          ;; Cancellation never blocks the caller behind a peer that stopped
          ;; reading. The dedicated writer serializes this with request output.
          (unless (eq? (unbox (outbound-request-state outbound)) 'queued)
            (unless (sync/timeout 0 (async-channel-put-evt (stdio-client-control c) (outbound-cancel outbound)))
              (error 'client "outbound cancellation queue exhausted"))))))))
(define (cancellation-wire id)
  (json->string (hasheq 'jsonrpc "2.0" 'method "notifications/cancelled"
                       'params (hasheq 'requestId id))))
(define (write-outbound! c item)
  (cond
    [(outbound-request? item)
     (define send?
       (call-with-semaphore (stdio-client-lock c)
         (lambda ()
           (cond [(hash-has-key? (stdio-client-pending c) (outbound-request-id item))
                  (set-box! (outbound-request-state item) 'writing) #t]
                 [else
                  (set-box! (outbound-request-state item) 'skipped)
                  (finish-request! c (outbound-request-id item) #f)
                  #f]))))
     (when send?
       (client-send! c (outbound-request-wire item))
       (set-box! (outbound-request-state item) 'sent))]
    [(outbound-cancel? item)
     (define request (outbound-cancel-request item))
     (when (eq? (unbox (outbound-request-state request)) 'sent)
       (client-send! c (cancellation-wire (outbound-request-id request))))]))
(define (client-send! c wire)
  ;; Never hold the state lock while writing: EOF/close must resolve pending
  ;; handles even when a peer stops consuming our output.
  (with-handlers ([exn:fail? (lambda (e) (client-close! c e) (raise e))])
    (call-with-semaphore
     (stdio-client-writer-lock c)
     (lambda ()
       (when (stdio-client-closed? c) (error 'client "client is closed"))
       (display wire (stdio-client-out c)) (newline (stdio-client-out c))
       (flush-output (stdio-client-out c))))))
(define (client-request c method [params (hasheq)] #:capabilities [caps (hasheq)]
                        #:timeout [timeout (and (not (equal? method "subscriptions/listen")) (stdio-client-timeout c))])
  (check-timeout timeout)
  (define started (current-inexact-monotonic-milliseconds))
  (set! method (string->immutable-string method))
  (define request-caps (string->json (json->string caps)))
  (define meta (request-meta #:capabilities request-caps #:extra (hash-ref params '_meta (hasheq))))
  (define raw-token (hash-ref meta 'progressToken missing))
  (define token (if (string? raw-token) (string->immutable-string raw-token) raw-token))
  (unless (or (missing? token) (string? token) (exact-integer? token))
    (raise-argument-error 'client-request "string or integer progressToken" token))
  (define handle
    (call-with-semaphore
     (stdio-client-lock c)
     (lambda ()
       (when (stdio-client-closed? c) (error 'client-request "client is closed"))
       (when (>= (hash-count (stdio-client-pending c)) (stdio-client-request-limit c))
         (error 'client-request "Active request limit exceeded"))
       (when (and (not (missing? token)) (hash-has-key? (stdio-client-tokens c) token))
         (error 'client-request "progressToken already belongs to an active request"))
       (when (and (not (missing? token)) (>= (hash-count (stdio-client-tokens c)) (stdio-client-progress-token-limit c)))
         (error 'client-request "Progress token limit exceeded; unresolved cancelled tokens require a fresh connection"))
       (define id (add1 (stdio-client-next-id c)))
       ;; Encode before registration so bad local data cannot leave a pending call.
       (define wire (json->string (hasheq 'jsonrpc "2.0" 'id id 'method method
                                         'params (hash-set params '_meta meta))))
       (define outbound (outbound-request id wire (box 'queued)))
       (define h
         (request-handle
          id (make-semaphore 0) (box #f)
          (lambda () (cancel-request! c id))
          (make-async-channel (stdio-client-notification-limit c))))
       (set-stdio-client-next-id! c id)
       (hash-set! (stdio-client-pending c) id (pending-request h token request-caps (make-progress-tracker token) method outbound))
       (unless (missing? token) (hash-set! (stdio-client-tokens c) token id))
       (unless (sync/timeout 0 (async-channel-put-evt (stdio-client-control c) outbound))
         (finish-request! c id #f)
         (error 'client-request "Outbound queue limit exceeded"))
       h)))
  (when timeout
    (thread
     (lambda ()
       (define event
         (sync (wrap-evt handle (lambda (_) 'done))
               (wrap-evt (alarm-evt (+ started (* 1000 timeout)) #t) (lambda (_) 'timeout))))
       (when (eq? event 'timeout)
         (cancel-request! c (request-handle-id handle)
           (exn:fail:request-timeout (format "Request deadline exceeded (~a seconds)" timeout)
                                    (current-continuation-marks) (request-handle-id handle) timeout))))))
  handle)
(define (client-call c method [params (hasheq)] #:capabilities [caps (hasheq)]
                     #:timeout [timeout (and (not (equal? method "subscriptions/listen")) (stdio-client-timeout c))])
  (define result (sync (client-request c method params #:capabilities caps #:timeout timeout)))
  (if (exn? result) (raise result) result))
(define (client-close! c [reason (exn:fail "Client closed" (current-continuation-marks))])
  (define first?
    (call-with-semaphore
     (stdio-client-lock c)
     (lambda ()
       (and (not (stdio-client-closed? c))
            (begin
              (set-stdio-client-closed?! c #t)
              (for ([id (in-list (hash-keys (stdio-client-pending c)))])
                (finish-request! c id reason))
              (hash-clear! (stdio-client-tokens c))
              #t)))))
  (when first?
    ;; Cleanup attempts both halves even if one port's close procedure fails.
    (when (stdio-client-close-ports? c)
      (for ([close (in-list (list (lambda () (close-input-port (stdio-client-in c)))
                                 (lambda () (close-output-port (stdio-client-out c)))))])
        (with-handlers ([exn:fail? void]) (close))))
    (for ([worker (in-list (list (stdio-client-reader c) (stdio-client-control-worker c)))])
      (when (and worker (not (eq? worker (current-thread)))) (kill-thread worker)))))
