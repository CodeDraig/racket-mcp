#lang racket/base
(provide current-task-executor current-task-recovery-check current-task-resumption)
(define current-task-executor (make-parameter #f))
(define current-task-recovery-check (make-parameter (lambda (_instance) (void))))
(define current-task-resumption (make-parameter #f))
