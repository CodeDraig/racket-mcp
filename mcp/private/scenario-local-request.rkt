#lang racket/base
(require racket/async-channel "../runtime.rkt" "../json.rkt" "../subscription.rkt" "request-handle.rkt")
(provide make-local-request)
(define (make-local-request rt principal)
  (define ids (box 0))
  (define (next-id)
    (let loop ()
      (define old (unbox ids))
      (if (box-cas! ids old (add1 old)) (add1 old) (loop))))
  (lambda (method params caps timeout)
    (define id (next-id))
    (define message (string->json (json->string
      (hasheq 'jsonrpc "2.0" 'id id 'method method
              'params (hash-set params '_meta (request-meta #:capabilities caps #:extra (hash-ref params '_meta (hasheq))))))))
    (define owner (make-custodian))
    (define ready (make-semaphore 0))
    (define result (box #f))
    (define lock (make-semaphore 1))
    (define notices (make-async-channel 256))
    (define cancelled (make-semaphore 0))
    (define (finish! value [cancel? #f])
      (call-with-semaphore lock
        (lambda ()
          (cond [(sync/timeout 0 (semaphore-peek-evt ready)) #f]
                [else
                 (when cancel? (semaphore-post cancelled))
                 (set-box! result value) (semaphore-post ready) #t]))))
    (define (cancel! reason)
      (finish! reason #t))
    (define handle
      (request-handle id ready result
        (lambda () (cancel! (exn:fail:request-cancelled "Scenario request cancelled" (current-continuation-marks) id)))
        notices))
    (define worker
      (parameterize ([current-custodian owner])
        (thread
          (lambda ()
            (parameterize ([current-output-port (current-error-port)]
                           [current-cancellation-event (semaphore-peek-evt cancelled)]
                           [current-cancelled? (lambda () (and (sync/timeout 0 (semaphore-peek-evt cancelled)) #t))])
              (with-handlers ([(lambda (_) #t)
                              (lambda (failure)
                                (finish! (if (exn? failure) failure
                                  (exn:fail (format "Scenario worker raised: ~e" failure) (current-continuation-marks)))))])
                (finish!
                  (dispatch-message rt message #:principal principal
                    #:notify (lambda (notice)
                               (unless (sync/timeout 0 (async-channel-put-evt notices notice))
                                 (cancel! (exn:fail:notification-overflow
                                           "Scenario notification queue overflow" (current-continuation-marks) id))))))))))))
    ;; The supervisor belongs to the session, outside the request's custodian.
    (thread
      (lambda ()
        (define done (sync/timeout timeout handle worker))
        (cond [(not done)
               (cancel! (exn:fail:request-timeout "Scenario request timed out" (current-continuation-marks) id timeout))]
              [(eq? done worker)
               (finish! (exn:fail "Scenario request worker terminated" (current-continuation-marks)))])
        (when (sync/timeout 0 (semaphore-peek-evt cancelled)) (sync/timeout 0.2 worker))
        (custodian-shutdown-all owner)))
    handle))

