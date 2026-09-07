#lang racket/base
(require db racket/async-channel)
(provide call-with-owned-transaction)
(struct transaction-aborted exn:fail ())
;; The supervisor owns the managed database transaction and semaphore. The
;; application procedure stays in its calling thread and parameterization.
(define (call-with-owned-transaction connection lock custodian proc)
  (define requester (current-thread))
  (define ready (make-async-channel))
  (define finished (make-semaphore 0))
  (define released (make-async-channel))
  (define failed? #f)
  (define succeeded? #f)
  (define breaks? (break-enabled))
  (parameterize-break #f
    (define supervisor
      (parameterize ([current-custodian custodian])
        (thread
         (lambda ()
           (with-handlers ([(lambda (_) #t)
                            (lambda (failure)
                              (async-channel-put ready (cons #f failure))
                              (async-channel-put released (cons #f failure)))])
             (define acquired?
               (sync (wrap-evt lock (lambda (_) #t))
                     (wrap-evt (semaphore-peek-evt finished) (lambda (_) #f))
                     (wrap-evt (thread-dead-evt requester) (lambda (_) #f))))
             (when acquired?
               (dynamic-wind void
               (lambda ()
                 (with-handlers ([(lambda (_) #t)
                                  (lambda (failure)
                                    ;; Check/discard the connection while still owning
                                    ;; its lock: a later transaction may already be
                                    ;; running once the dynamic-wind releases it.
                                    (with-handlers ([(lambda (_) #t) void])
                                      (when (and (connected? connection) (in-transaction? connection))
                                        (disconnect connection)))
                                    (raise failure))])
                  (with-handlers ([transaction-aborted? void])
                   (call-with-transaction connection
                     (lambda ()
                       (async-channel-put ready (cons #t #f))
                       (define normal-exit?
                         (sync (wrap-evt (semaphore-peek-evt finished) (lambda (_) #t))
                               (wrap-evt (thread-dead-evt requester) (lambda (_) #f))))
                       (unless (and normal-exit? succeeded? (not (thread-dead? requester)))
                         ;; db catches exceptions, not arbitrary raised values.
                         ;; This private exception requests rollback only.
                         (raise (transaction-aborted "Transaction abandoned" (current-continuation-marks)))))
                     #:option 'immediate))))
               (lambda () (semaphore-post lock))))
             (async-channel-put released (cons #t #f)))))))
    (define (receive channel)
      (sync channel
            (wrap-evt (thread-dead-evt supervisor)
                      (lambda (_)
                        (or (sync/timeout 0 channel)
                            (cons #f (exn:fail "Transaction supervisor terminated" (current-continuation-marks))))))))
    (dynamic-wind void
      (lambda ()
        (parameterize-break breaks?
          (with-handlers ([(lambda (_) #t) (lambda (failure) (set! failed? #t) (set! succeeded? #f) (raise failure))])
            (define acquired (receive ready))
            (unless (car acquired) (raise (cdr acquired)))
            (call-with-continuation-barrier
             (lambda ()
               (call-with-values proc
                 (lambda results (set! succeeded? #t) (apply values results))))))))
      (lambda ()
        (semaphore-post finished)
        (define cleanup (receive released))
        (when (and (not (car cleanup)) (not failed?)) (raise (cdr cleanup)))))))
