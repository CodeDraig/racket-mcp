#lang racket/base
(require rackunit racket/runtime-path mcp "lang-marker.rkt")
(define-runtime-path source "lang-probe.rkt")
(void (dynamic-require `(submod (file ,(path->string source)) manifest) 'manifest))
(check-false (unbox loaded))
(define interface (dynamic-require source 'mcp-interface))
(check-true (unbox loaded))
(check-equal? (dynamic-require source 'expansion-count) 1)
(define store (open-memory-store))
(define runtime (make-runtime interface #:store store))
(dynamic-wind void
  (lambda ()
    (check-equal? (dispatch runtime "tools/call"
                  (hasheq '_meta (request-meta) 'name "language-match" 'arguments (hasheq 'items '("tag" "value"))))
                  (text-result "value"))
    (check-equal? (dynamic-require source 'calls) 1))
  (lambda () (custodian-shutdown-all (runtime-custodian runtime)) (close-store! store)))
