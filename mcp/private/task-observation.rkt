#lang racket/base
;; Trusted local observation context; no wire parameter can install it.
(provide current-upstream-task-observation (struct-out task-subscription-target))
(define current-upstream-task-observation (make-parameter #f))
(struct task-subscription-target (snapshot) #:transparent)
