#lang racket/base
(require compiler/find-exe racket/runtime-path racket/system)
(provide run-command)
(define-runtime-path command "../command.rkt")
;; raco has already loaded ordinary libraries before dispatching this module.
;; Start the kernel entry in a fresh process rather than assigning identities to
;; those unobserved instances. Arguments are passed directly, without a shell.
(define (run-command [arguments (current-command-line-arguments)])
  (unless (and (vector? arguments) (for/and ([arg (in-vector arguments)]) (string? arg)))
    (raise-argument-error 'run-command "vector of command argument strings" arguments))
  (define owner (make-custodian))
  (dynamic-wind
    void
    (lambda ()
      (parameterize ([current-custodian owner] [current-subprocess-custodian-mode 'kill])
        (apply system*/exit-code (find-exe) command (vector->list arguments))))
    (lambda () (custodian-shutdown-all owner))))
(module+ main (exit (run-command)))
