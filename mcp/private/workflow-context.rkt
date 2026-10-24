#lang racket/base
(require "../storage.rkt")
(provide (struct-out exn:fail:recovery) recovery current-workflow-change-publisher
         current-workflow-store current-workflow-adapters current-workflow-state current-workflow-responses
         current-workflow-invocation-key current-workflow-task-handoff)
(struct exn:fail:recovery exn:fail (handle stage) #:transparent)
(define current-workflow-change-publisher (make-parameter void))
(define current-workflow-store (make-parameter #f))
(define current-workflow-adapters (make-parameter (hasheq)))
(define current-workflow-state (make-parameter #f))
(define current-workflow-responses (make-parameter (hasheq)))
(define current-workflow-invocation-key (make-parameter #f))
;; Installed only by the Tasks entry point; background task workers clear it.
(define current-workflow-task-handoff (make-parameter #f))
(define (recovery instance stage message)
  (raise (exn:fail:recovery message (current-continuation-marks) (stored-instance-handle instance) stage)))
