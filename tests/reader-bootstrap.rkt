#lang racket/base
(require rackunit racket/file racket/runtime-path racket/port compiler/cm mcp/scenario mcp/private/module-observation)
(define-runtime-path fixture "../dev/command-observation-server.rkt")
(test-case "cold source entry captures ordinary bootstrap dependencies"
  (define directory (make-temporary-file "mcp-reader-bootstrap-~a" 'directory))
  (define application (build-path directory "application.rkt"))
  (dynamic-wind void
    (lambda ()
      ;; A new path has no compiled application; dependency libraries may use
      ;; their installed bytecode, as in normal direct source execution.
      (copy-file fixture application)
      (call-with-scenario-process (list (find-executable-path "racket") application)
        (lambda (session)
          (define response (scenario-process-call session "tools/call" (hasheq 'name "capture-baseline")))
          (check-false (hash-has-key? response 'error))
          (define data (read (open-input-string
                              (hash-ref (car (hash-ref (hash-ref response 'result) 'content)) 'text))))
          (check-equal? (caddr data) '())
          (check-true (pair? (car data)))
          (check-equal? (car data) (cadr data))) #:timeout 30))
    (lambda () (delete-directory/files directory))))
(test-case "reader preserves the standard export arities"
  (for ([name '(read read-syntax get-info get-interaction-info)] [arity '(5 6 5 1)])
    (check-equal? (procedure-arity (dynamic-require 'mcp/lang/reader name)) arity)))

(define-runtime-path kernel-worker "../dev/kernel-observation-worker.rkt")
(test-case "stamped kernel entry preserves cold runtime observation"
  (define directory (make-temporary-file "mcp-stamped-kernel-~a" 'directory))
  (define worker (build-path directory "worker.rkt"))
  (dynamic-wind void
    (lambda ()
      (copy-file kernel-worker worker)
      (call-with-module-observation (lambda () (managed-compile-zo worker)))
      (define-values (process out in err)
        (subprocess #f #f #f (find-executable-path "racket") worker fixture))
      (close-output-port in)
      (define watchdog (thread (lambda () (unless (sync/timeout 30 process) (subprocess-kill process #t)))))
      (define output (port->string out))
      (define errors (port->string err))
      (subprocess-wait process) (thread-wait watchdog)
      (close-input-port out) (close-input-port err)
      (check-equal? (subprocess-status process) 0 errors)
      (check-equal? (car (read (open-input-string output))) 'ordinary))
    (lambda () (delete-directory/files directory))))
