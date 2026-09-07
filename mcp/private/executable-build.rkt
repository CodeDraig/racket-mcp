#lang racket/base
(provide current-executable-build make-executable-build
         seal-executable-build! executable-build-fingerprint call-with-executable-build)
;; Shared with the application's namespace before its descriptors are created.
;; The build is sealed only after loading finishes and every dependency has an
;; explicit identity. Descriptors retain this cell, never a mutable source path.
(struct executable-build (value lock runner) #:mutable)
(define current-executable-build (make-parameter #f))
(define (make-executable-build) (executable-build #f (make-semaphore 1) (lambda (thunk) (thunk))))
(define (executable-build-fingerprint build)
  (or (executable-build-value build)
      (error 'workflow "executable capture is not sealed; dependency identities are incomplete")))
(define (seal-executable-build! build fingerprint #:runner [runner (lambda (thunk) (thunk))])
  (unless (and (string? fingerprint) (positive? (string-length fingerprint)))
    (raise-argument-error 'seal-executable-build! "nonempty fingerprint string" fingerprint))
  (unless (and (procedure? runner) (procedure-arity-includes? runner 1))
    (raise-argument-error 'seal-executable-build! "unary execution scope" runner))
  (call-with-semaphore (executable-build-lock build)
    (lambda ()
      (when (executable-build-value build)
        (error 'seal-executable-build! "executable capture is already sealed"))
      (set-executable-build-runner! build runner)
      (set-executable-build-value! build (string->immutable-string fingerprint)))))

(define (call-with-executable-build build thunk)
  (executable-build-fingerprint build)
  ((executable-build-runner build) thunk))
