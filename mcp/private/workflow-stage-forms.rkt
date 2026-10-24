#lang racket/base
(require (for-syntax racket/base))
(provide checkpoint await-input perform task-boundary)
(define-syntax (checkpoint stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
(define-syntax (await-input stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
(define-syntax (perform stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
(define-syntax (task-boundary stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
