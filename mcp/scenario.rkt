#lang racket/base
(require "scenario-session.rkt" "scenario-process.rkt" racket/path raco/testing)
(provide run-scenarios (all-from-out "scenario-session.rkt" "scenario-process.rkt"))

;; Run an authored test submodule in its own module registry and custodian.
;; RackUnit catches assertion failures, so successful module instantiation alone
;; is not a successful scenario. Other Racket frameworks can use the same log.
(define (run-scenarios path)
  (unless (path-string? path) (raise-argument-error 'run-scenarios "path-string?" path))
  (define target `(submod (file ,(path->string (path->complete-path path))) test))
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner] [current-namespace (make-base-namespace)])
        (define report (dynamic-require 'raco/testing 'test-report))
        (dynamic-require target #f)
        (define result (report #:display? #t))
        (unless (zero? (car result))
          (error 'scenario "~a of ~a tests failed" (car result) (cdr result)))
        result))
    (lambda () (custodian-shutdown-all owner))))
