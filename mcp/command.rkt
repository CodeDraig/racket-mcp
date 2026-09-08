#lang racket/base
;; Keep the executable entry point independent of SDK initialization. A bootstrap
;; loader must be able to install code-observation hooks before loading the CLI.
(provide main)
(define cli-path
  (module-path-index-join "cli.rkt" (variable-reference->module-path-index (#%variable-reference))))
(define (main)
  ((dynamic-require (module-path-index-resolve cli-path) 'main)))
(module+ main (main))
