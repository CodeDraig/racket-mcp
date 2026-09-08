#lang racket/base
(require rackunit racket/runtime-path mcp/scenario)
(define-runtime-path server "../dev/command-observation-server.rkt")
(define-runtime-path command "../mcp/command.rkt")
;; Exercise both the file main submodule and the library entry used by serving.
(for ([entry (list (list (find-executable-path "racket") command)
                   (list (find-executable-path "racket") "-l" "mcp/command" "--")
                   (list (find-executable-path "raco") "mcp"))])
  (test-case (format "command captures ordinary dependencies: ~s" entry)
    (call-with-scenario-process (append entry (list "serve" server))
      (lambda (session)
        (define response (scenario-process-call session "tools/call" (hasheq 'name "observed-build")))
        (check-false (hash-has-key? response 'error) (format "~s" response))
        (define result (hash-ref response 'result))
        (check-equal? (hash-ref result 'resultType) "complete")
        (define counts
          (read (open-input-string (hash-ref (car (hash-ref result 'content)) 'text))))
        (check-true (> (car counts) 20))
        (check-true (> (cadr counts) 0))
        (check-equal? (caddr counts) '())
        (define baseline-response
          (scenario-process-call session "tools/call" (hasheq 'name "capture-baseline")))
        (check-false (hash-has-key? baseline-response 'error) (format "~s" baseline-response))
        (define baseline
          (read (open-input-string
                  (hash-ref (car (hash-ref (hash-ref baseline-response 'result) 'content)) 'text))))
        ;; Capture includes all observed dynamic declarations as well as static
        ;; imports. Every ordinary dependency must have actual code evidence.
        (check-equal? (caddr baseline) '())
        (check-true (pair? (car baseline)))
        (check-equal? (car baseline) (cadr baseline)))
      #:timeout 15)))
