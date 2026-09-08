#lang racket/base
(require "helper.rkt")
(module configure-runtime racket/base
  (displayln "CONFIGURE")
  (define original (current-eval))
  (current-eval
    (lambda (code)
      (when (compiled-module-expression? code)
        (printf "EVAL ~s ~s\n" (current-module-declare-name) (module-compiled-name code)))
      (original code))))
(displayln (greeting))
(module+ main (displayln "MAIN"))
