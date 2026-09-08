#lang racket/base
(provide install!)
(define (install!)
  (displayln "INSTALL")
  (define original (current-eval))
  (current-eval
    (lambda (code)
      (printf "EVAL ~s compiled=~s syntax=~s\n" (current-module-declare-name) (compiled-module-expression? code) (syntax? code))
      (original code))))
