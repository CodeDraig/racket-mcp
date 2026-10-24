#lang racket/base
(require racket/list "request-handle.rkt" "upstream-snapshot.rkt" "upstream-subscription-state.rkt")
(provide call-with-upstream-subscription)
(define (call-with-upstream-subscription pinned request requested proc timeout
          filter-key change-method change-key forward make-subscription accepted->local ended)
  (define (send method params)
    (define handle (request method params))
    (unless (request-handle? handle)
      (error 'upstream-subscription "request callback must return a request handle"))
    handle)
  (check-upstream-compatibility! pinned
    (lambda (method params)
      (define handle (send method params))
      (dynamic-wind void
        (lambda ()
          (define value (sync/timeout timeout handle))
          (unless value (error 'upstream-subscription "snapshot request timed out: ~a" method))
          (when (exn? value) (raise value))
          value)
        (lambda () (unless (sync/timeout 0 handle) (request-cancel! handle))))))
  (define peer (send "subscriptions/listen" (hasheq 'notifications (hasheq filter-key requested))))
  (define notices (request-handle-notifications peer))
  (define owner (make-custodian))
  (define stopped (make-semaphore 0))
  (define stopped-evt (semaphore-peek-evt stopped))
  (define cancellation
    (exn:fail:request-cancelled "Upstream subscription cancelled locally"
      (current-continuation-marks) (request-handle-id peer)))
  (define (cancel!)
    ;; Wake the forwarding worker before contacting the borrowed client. Local
    ;; cancellation abandons queued changes; normal completion still drains them.
    (semaphore-post stopped)
    (request-cancel! peer))
  (define worker #f)
  (define subscription #f)
  (define lock (make-semaphore 1))
  (define finalizing? #f)
  (define (finish! value #:fallback? [fallback? #f])
    (define claimed?
      (call-with-semaphore lock
        (lambda ()
          (cond [(sync/timeout 0 (semaphore-peek-evt (upstream-subscription-ready subscription))) #f]
                [finalizing? fallback?]
                [else (set! finalizing? #t)
                      (set-box! (upstream-subscription-outcome subscription) value) #t]))))
    (when claimed?
      (define outcome (unbox (upstream-subscription-outcome subscription)))
      (dynamic-wind void
        (lambda ()
          (ended (upstream-subscription-accepted subscription)
                 (or fallback?
                     (not (or (exn:fail:request-cancelled? outcome)
                              (and (hash? outcome) (not (hash-has-key? outcome 'error))
                                   (hash-has-key? outcome 'result))))) fallback?))
        (lambda () (semaphore-post (upstream-subscription-ready subscription))))))
  (define (tagged-params message)
    (unless (hash? message) (error 'upstream-subscription "expected a notification object"))
    (define params (hash-ref message 'params #f))
    (unless (and (hash? params) (hash? (hash-ref params '_meta #f))
                 (equal? (hash-ref (hash-ref params '_meta) 'io.modelcontextprotocol/subscriptionId #f)
                         (request-handle-id peer)))
      (error 'upstream-subscription "notification has an incorrect subscription ID"))
    params)
  (define events
    (choice-evt (wrap-evt notices (lambda (notice) (cons 'notice notice)))
                (wrap-evt peer (lambda (outcome) (cons 'outcome outcome)))
                (wrap-evt stopped-evt (lambda (_) (cons 'stopped #f)))))
  (define (next-event wait)
    (define queued (sync/timeout 0 notices))
    (define event (if queued (cons 'notice queued) (sync/timeout wait events)))
    ;; Completion may become ready between the first queue check and sync.
    (cond [(sync/timeout 0 stopped-evt) (cons 'stopped #f)]
          [(and event (eq? (car event) 'outcome))
        (let ([last-notice (sync/timeout 0 notices)])
          (if last-notice (cons 'notice last-notice) event))]
          [else event]))
  (define (terminal outcome)
    (cond [(exn? outcome) outcome]
          [(and (hash? outcome) (hash-has-key? outcome 'error)) outcome]
          [else
           (define result (and (hash? outcome) (hash-ref outcome 'result #f)))
           (unless (and (hash? result) (equal? (hash-ref result 'resultType #f) "complete")
                        (hash? (hash-ref result '_meta #f))
                        (equal? (hash-ref (hash-ref result '_meta) 'io.modelcontextprotocol/subscriptionId #f)
                                (request-handle-id peer)))
             (error 'upstream-subscription "invalid subscription completion result"))
           outcome]))
  (dynamic-wind void
    (lambda ()
      (define first (next-event timeout))
      (unless first (error 'upstream-subscription "acknowledgement timed out"))
      (when (eq? (car first) 'outcome)
        (if (exn? (cdr first)) (raise (cdr first))
            (error 'upstream-subscription "subscription completed before acknowledgement: ~s" (cdr first))))
      (define params (tagged-params (cdr first)))
      (unless (equal? (hash-ref (cdr first) 'method #f) "notifications/subscriptions/acknowledged")
        (error 'upstream-subscription "expected acknowledgement before changes"))
      (define accepted (hash-ref params 'notifications #f))
      (unless (and (hash? accepted)
                   (andmap (lambda (key) (eq? key filter-key)) (hash-keys accepted))
                   (list? (hash-ref accepted filter-key '()))
                   (andmap (lambda (uri) (and (string? uri) (member uri requested)))
                           (hash-ref accepted filter-key '())))
        (error 'upstream-subscription "acknowledgement contains an unrequested filter"))
      (define accepted-ids (remove-duplicates (map string->immutable-string (hash-ref accepted filter-key '()))))
      (set! subscription
        (make-subscription (make-semaphore 0) (box #f)
          cancel! (accepted->local accepted-ids)))
      (set! worker
        (parameterize ([current-custodian owner])
          (thread
            (lambda ()
              (with-handlers ([(lambda (_) #t)
                               (lambda (failure)
                                 (finish! (if (exn? failure) failure
                                              (exn:fail (format "Upstream forwarding raised: ~s" failure) (current-continuation-marks))))
                                 (cancel!))])
                (let loop ()
                  ;; Drain already queued notices before observing stream completion.
                  (define event (next-event #f))
                  (cond
                    [(eq? (car event) 'stopped) (finish! cancellation)]
                    [(eq? (car event) 'outcome) (finish! (terminal (cdr event)))]
                    [else
                     (define notice (cdr event))
                     (define values (tagged-params notice))
                     (define id (hash-ref values change-key #f))
                     (unless (and (equal? (hash-ref notice 'method #f) change-method)
                                  (member id accepted-ids))
                       (error 'upstream-subscription "received an unaccepted ~a change"
                              (if (eq? filter-key 'taskIds) "task" "resource")))
                     (forward id values)
                     (loop)])))))))
      (proc subscription))
    (lambda ()
      (parameterize-break #f
        (with-handlers ([(lambda (_) #t) void]) (cancel!))
        (when worker (sync/timeout timeout worker))
        (custodian-shutdown-all owner)
        (when subscription
          ;; The worker is gone. Do not repeat application dependency callbacks
          ;; that may have been interrupted during forward/termination handling.
          (finish! cancellation #:fallback? #t))))))
