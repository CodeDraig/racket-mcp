#lang racket/base

(provide (struct-out request-context) current-request-context current-interface current-resource-resolver)
(struct request-context (principal capabilities request-id cancelled? notify) #:transparent)
(define current-request-context (make-parameter #f))
(define current-interface (make-parameter #f))
(define current-resource-resolver (make-parameter (lambda (_) (error 'embed "no active resource resolver"))))
