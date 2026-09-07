#lang racket/base
;; Trusted local observation context; no wire parameter can install it.
(provide current-upstream-task-observation)
(define current-upstream-task-observation (make-parameter #f))
