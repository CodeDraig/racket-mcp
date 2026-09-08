#lang racket/base
(require "../schema.rkt" "../json.rkt" "../error.rkt" "elicitation-format.rkt")
(provide validate-input-response)
(define (validate-input-response request response)
  (unless (and (hash? response) (member (hash-ref response 'action #f) '("accept" "decline" "cancel")))
    (mcp-error -32602 "Invalid elicitation response action"))
  (when (and (equal? (hash-ref response 'action) "accept") (equal? (hash-ref request 'mode "form") "form"))
    (define schema (hash-ref request 'requestedSchema))
    (define content (hash-ref response 'content json-null))
    (unless (valid? schema content)
      (mcp-error -32602 "Elicitation content failed the requested schema"))
    (for ([(key property) (in-hash (hash-ref schema 'properties (hasheq)))]
          #:when (and (hash? property) (hash-has-key? property 'format)
                      (hash? content) (hash-has-key? content key)))
      (unless (elicitation-format-valid? (hash-ref property 'format) (hash-ref content key))
        (mcp-error -32602 "Elicitation content failed its declared format"
                   (hasheq 'property (symbol->string key) 'format (hash-ref property 'format)))))))
