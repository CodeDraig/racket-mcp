#lang racket/base
(require "../schema.rkt" "../json.rkt" "../error.rkt")
(provide validate-input-response)
(define (validate-input-response request response)
  (unless (and (hash? response) (member (hash-ref response 'action #f) '("accept" "decline" "cancel")))
    (mcp-error -32602 "Invalid elicitation response action"))
  (when (and (equal? (hash-ref response 'action) "accept") (equal? (hash-ref request 'mode "form") "form")
             (not (valid? (hash-ref request 'requestedSchema) (hash-ref response 'content json-null))))
    (mcp-error -32602 "Elicitation content failed the requested schema")))
