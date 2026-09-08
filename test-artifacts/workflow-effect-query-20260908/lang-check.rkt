#lang racket/base
(require rackunit racket/runtime-path mcp "lang-marker.rkt")
(define-runtime-path source "lang-probe.rkt")
(define manifest (dynamic-require `(submod ,source manifest) 'manifest))
(check-false (unbox loaded))
(check-true (list? manifest))
(define interface (dynamic-require source 'mcp-interface))
(check-true (unbox loaded))
(define store (open-memory-store))
(define rt (make-runtime interface #:store store
  #:adapters (hasheq 'writer (effect-adapter 'idempotent (lambda (value _key _tx) value)))))
(dynamic-wind void
  (lambda ()
    (check-equal? (dispatch rt "tools/call"
      (hasheq '_meta (request-meta) 'name "write-message" 'arguments (hasheq 'writer "message")))
      (text-result "message")))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
