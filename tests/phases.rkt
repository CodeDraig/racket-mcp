#lang racket/base
(require rackunit racket/runtime-path racket/system)
(define-runtime-path probe "../dev/check-phase-references.rkt")
;; The probe runs each phase in an independent bounded child process. Its
;; minimal syntax-spec language imports no MCP implementation code.
(check-equal? (system*/exit-code (find-executable-path "racket") probe) 0)
