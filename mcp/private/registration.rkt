#lang racket/base
(require racket/stxparam (for-syntax racket/base))
(provide register-declaration)
(define-syntax-parameter register-declaration (lambda (stx) #'(void)))
