#lang racket/base
(require "format-date.rkt" "format-uri.rkt" "format-email.rkt")
(provide elicitation-format-valid?)
(define (elicitation-format-valid? name value)
  (or (not (string? value))
       (case (string->symbol name)
         [(date) (and (date-parts value) #t)]
         [(date-time) (timestamp? value)]
         [(email) (email? value)]
         [(uri) (uri? value)]
         [else #f])))
