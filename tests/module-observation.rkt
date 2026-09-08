#lang racket/base
(require rackunit racket/file racket/port mcp/private/module-observation)
(define directory (make-temporary-file "mcp-module-observation-~a" 'directory))
(define path (build-path directory "helper.rkt"))
(define identity (make-resolved-module-path path))
(define (write-helper value)
  (call-with-output-file path #:exists 'truncate
    (lambda (out) (fprintf out "#lang racket/base\n(provide value)\n(define value ~s)\n" value))))
(define (bytes-of code) (call-with-output-bytes (lambda (out) (write code out))))
(dynamic-wind void
  (lambda ()
    (write-helper "before")
    (define first (make-base-namespace))
    (define second (make-base-namespace))
    (check-false (observed-module-code identity first))
    (call-with-module-observation
      (lambda ()
        (parameterize ([current-namespace first])
          (check-equal? (dynamic-require path 'value) "before"))
        (define before (observed-module-code identity first))
        (check-true (compiled-module-expression? before))
        (check-false (observed-module-code identity second))
        (write-helper "after")
        ;; A changed file must not replace the evidence of code already loaded.
        (parameterize ([current-namespace first])
          (check-equal? (dynamic-require path 'value) "before"))
        (check-eq? (observed-module-code identity first) before)
        (parameterize ([current-namespace second])
          (check-equal? (dynamic-require path 'value) "after"))
        (check-not-equal? (bytes-of before) (bytes-of (observed-module-code identity second)))
        ;; A new observation cannot claim code merely because it was loaded by a
        ;; prior observation, even when both scopes share a module registry.
        (call-with-module-observation
          (lambda ()
            (parameterize ([current-namespace first]) (dynamic-require path 'value))
            (check-false (observed-module-code identity first))))
        (check-eq? (observed-module-code identity first) before)))
    (check-false (observed-module-code identity first)))
  (lambda () (delete-directory/files directory)))
