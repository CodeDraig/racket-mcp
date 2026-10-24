#lang racket/base
(require "../descriptor.rkt" "progress.rkt")
(provide current-cancellation-event current-cancelled? current-progress-token progress!)
(define current-cancellation-event (make-parameter never-evt))
(define current-cancelled? (make-parameter (lambda () #f)))
(define current-progress-token (make-parameter #f))
(define (progress! token progress #:total [total #f] #:message [message #f])
  (unless (current-request-context) (error 'progress! "no active request"))
  (when ((current-cancelled?)) (error 'progress! "request cancelled"))
  (emit-progress!
   (let* ([p (hasheq 'progressToken token 'progress progress)]
          [p (if total (hash-set p 'total total) p)])
     (if message (hash-set p 'message message) p))))
