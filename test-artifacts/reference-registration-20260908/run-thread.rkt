#lang racket/base
(require racket/runtime-path)
(define-runtime-path provider "provider.rkt")
(parameterize ([use-compiled-file-paths null])
 (thread-wait (thread (lambda () (displayln (dynamic-require provider 'value)))))
 (displayln (dynamic-require provider 'value)))
