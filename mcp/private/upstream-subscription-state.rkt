#lang racket/base

(provide (struct-out upstream-subscription) upstream-resource-subscription upstream-resource-subscription?
         upstream-task-subscription upstream-task-subscription? upstream-resource-subscription-accepted
         upstream-task-subscription-accepted stop-upstream-resource-subscription! stop-upstream-task-subscription!)
(struct upstream-subscription (ready outcome cancel accepted)
  #:property prop:evt
  (lambda (self)
    (wrap-evt (semaphore-peek-evt (upstream-subscription-ready self))
              (lambda (_) (unbox (upstream-subscription-outcome self))))))
(struct upstream-resource-subscription upstream-subscription ())
(struct upstream-task-subscription upstream-subscription ())
(define upstream-resource-subscription-accepted upstream-subscription-accepted)
(define upstream-task-subscription-accepted upstream-subscription-accepted)
(define (stop-upstream-resource-subscription! subscription)
  ((upstream-subscription-cancel subscription)))
(define stop-upstream-task-subscription! stop-upstream-resource-subscription!)
