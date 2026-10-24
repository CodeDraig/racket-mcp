#lang racket/base
(require "workflow-compiler.rkt" (for-syntax racket/base))
(provide workflow)
(define-syntax (workflow stx) (compile-workflow stx #f))
