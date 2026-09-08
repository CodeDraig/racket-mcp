#lang racket/base
(require mcp/scenario mcp/json)
(define root (current-directory))
(for ([entry (list (list (find-executable-path "racket") "/tmp/mcp-configure-scoped-server.rkt"))])
  (call-with-scenario-process entry
    (lambda (session)
      (define result (scenario-process-call session "tools/call" (hasheq 'name "capture-baseline")))
      (define data (read (open-input-string (hash-ref (car (hash-ref (hash-ref result 'result) 'content)) 'text))))
      (write-json (hasheq 'entry (map (lambda (v) (format "~a" v)) entry)
                          'unobserved (car data) 'predefined (cadr data) 'ordinary (caddr data)))
      (newline)) #:timeout 30))
