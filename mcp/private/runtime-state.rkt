#lang racket/base
(require "../build.rkt" "../clock.rkt")
(provide (struct-out runtime) (struct-out clocked-runtime) runtime-build-identity runtime-clock define/clock)
(struct runtime (interface authorize store adapters custodian subscriptions cache cache-context cache-namespace pagination required-scopes) #:transparent)
(struct clocked-runtime runtime (clock build-id))
(define (runtime-build-identity rt)
  (if (clocked-runtime? rt) (clocked-runtime-build-id rt) (current-build-identity)))
(define (runtime-clock rt)
  (if (clocked-runtime? rt) (clocked-runtime-clock rt) (current-mcp-clock)))
(define-syntax-rule (define/clock (name rt . arguments) body ...)
  (define (name rt . arguments)
    (parameterize ([current-mcp-clock (runtime-clock rt)]
                   [current-build-identity (runtime-build-identity rt)]) body ...)))
