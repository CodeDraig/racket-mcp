#lang racket/base
(require racket/cmdline (submod "../build.rkt" private))
(provide read-serving-options)
(define (read-serving-options program)
  (define transport "stdio") (define state #f) (define port 8000) (define runtime-build-id #f) (define build-id #f)
  (define args
    (command-line #:program program
      #:once-each [("--transport") value "stdio or http" (set! transport value)]
      [("--state") value "SQLite state file" (set! state value)]
      [("--port") value "HTTP port" (set! port (string->number value))]
      [("--build-id") value "Declared application/runtime identity for ordinary loading" (set! build-id (normalize-build-identity value))]
      [("--runtime-build-id") value "Immutable SDK/runtime build identity for captured loading" (set! runtime-build-id value)]
      #:args args args))
  (values transport state port runtime-build-id build-id args))
