#lang racket/base
(require racket/runtime-path "../json.rkt" "../schema.rkt")
(provide task-schema-valid?)
(define-runtime-path schema-path "task-schema.json")
(define schema (call-with-input-file schema-path read-json))
(define (task-schema-valid? name value)
  (valid? (hash-set schema '$ref (string-append "#/$defs/" name)) value))
