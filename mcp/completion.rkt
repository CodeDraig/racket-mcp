#lang racket/base
(provide (struct-out completion-descriptor))
(struct completion-descriptor (target argument handler) #:transparent)
