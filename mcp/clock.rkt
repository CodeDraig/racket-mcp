#lang racket/base
(provide current-mcp-clock mcp-current-milliseconds mcp-current-seconds
         make-manual-clock manual-clock? manual-clock-advance!)

;; Logical protocol/application time, in Unix milliseconds. Scheduling deadlines
;; still use real alarm events; advancing this clock does not schedule threads.
(define (check-clock clock)
  (unless (and (procedure? clock) (procedure-arity-includes? clock 0))
    (raise-argument-error 'current-mcp-clock "procedure accepting zero arguments" clock))
  clock)
(define current-mcp-clock (make-parameter current-inexact-milliseconds check-clock))
(define (mcp-current-milliseconds)
  (define value ((current-mcp-clock)))
  (unless (rational? value)
    (raise-arguments-error 'mcp-current-milliseconds "clock must return finite real Unix milliseconds" "value" value))
  value)
(define (mcp-current-seconds)
  (inexact->exact (floor (/ (mcp-current-milliseconds) 1000))))

(struct manual-clock (lock [milliseconds #:mutable])
  #:property prop:procedure
  (lambda (clock)
    (call-with-semaphore (manual-clock-lock clock)
      (lambda () (manual-clock-milliseconds clock)))))
(define (make-manual-clock #:seconds [seconds 0])
  (unless (rational? seconds) (raise-argument-error 'make-manual-clock "finite real seconds" seconds))
  (manual-clock (make-semaphore 1) (* 1000 seconds)))
(define (manual-clock-advance! clock seconds)
  (unless (manual-clock? clock) (raise-argument-error 'manual-clock-advance! "manual-clock?" clock))
  (unless (and (rational? seconds) (>= seconds 0))
    (raise-argument-error 'manual-clock-advance! "finite nonnegative real seconds" seconds))
  (call-with-semaphore (manual-clock-lock clock)
    (lambda ()
      (set-manual-clock-milliseconds! clock (+ (manual-clock-milliseconds clock) (* 1000 seconds)))
      (manual-clock-milliseconds clock))))
