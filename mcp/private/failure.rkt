#lang racket/base
(provide non-break-failure? failure-message)
;; Racket permits any value to be raised. Breaks retain their control-flow
;; meaning; other values are failures at protocol/task boundaries.
(define (non-break-failure? value) (not (exn:break? value)))
(define (failure-message value)
  (if (exn? value) (exn-message value) "Non-exception value raised"))
