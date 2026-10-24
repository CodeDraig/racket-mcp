#lang racket/base

(provide (struct-out request-handle) request-cancel!
         (struct-out exn:fail:request-timeout) (struct-out exn:fail:request-cancelled)
         (struct-out exn:fail:notification-overflow))
(struct request-handle (id ready result cancel notifications) #:transparent
  #:property prop:evt (lambda (self) (wrap-evt (semaphore-peek-evt (request-handle-ready self))
                                             (lambda (_) (unbox (request-handle-result self))))))
(define (request-cancel! handle) ((request-handle-cancel handle)))
(struct exn:fail:request-timeout exn:fail (request-id seconds) #:transparent)
(struct exn:fail:request-cancelled exn:fail (request-id) #:transparent)
(struct exn:fail:notification-overflow exn:fail (request-id) #:transparent)
