#lang racket/base
(provide (struct-out completion-descriptor))
(struct completion-descriptor (target argument handler) #:transparent
  #:guard
  (lambda (target argument handler who)
    (unless (symbol? argument) (raise-argument-error who "symbol?" argument))
    (unless (and (procedure? handler) (procedure-arity-includes? handler 2))
      (raise-argument-error who "procedure accepting prefix and context" handler))
    ;; Target membership and argument resolution need the complete interface.
    (values target argument handler)))
