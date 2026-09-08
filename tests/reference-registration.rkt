#lang racket/base
(require rackunit racket/runtime-path)
(define-runtime-path provider "reference-registration-provider.rkt")
;; A fresh registry and source expansion prevent an earlier compiler visit from
;; concealing registrations that were confined to the visiting worker's parameter.
(parameterize ([current-namespace (make-base-namespace)] [use-compiled-file-paths null])
  (define (attempt)
    (with-handlers ([exn:fail? (lambda (error) (list 'error (exn-message error)))])
      (list 'ok (dynamic-require provider 'value))))
  (define (in-worker)
    (define result (make-channel))
    (define worker (thread (lambda () (channel-put result (attempt)))))
    (define answer (channel-get result))
    (thread-wait worker)
    answer)
  (check-equal? (in-worker) '(ok 7))
  (check-equal? (attempt) '(ok 7))
  (check-equal? (in-worker) '(ok 7)))
