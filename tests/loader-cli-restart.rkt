#lang racket/base
(require rackunit racket/file racket/port racket/runtime-path mcp/stdio)
(define-runtime-path cli "../mcp/cli.rkt")
(define (check-loader-entry command)
  (define directory (make-temporary-file "mcp-loader-cli-~a" 'directory))
  (define application (build-path directory "application.rkt"))
  (define helper (build-path directory "helper.rkt"))
  (define database (build-path directory "state.sqlite"))
  (define completed (build-path directory "completed.txt"))
  (define (write-helper value)
    (call-with-output-file helper #:exists 'truncate
      (lambda (out) (fprintf out "#lang racket/base\n(provide helper)\n(define (helper) ~s)\n" value))))
  (define (call build-id [state #f])
    (define-values (process out in err)
      (apply subprocess #f #f #f
             (append command
                     (list "--runtime-build-id" build-id "--state" database "serve" application))))
    (define client (make-stdio-client out in #:timeout 15))
    (dynamic-wind void
      (lambda ()
        (client-call client "tools/call"
          (if state
              (hasheq 'name "work" 'requestState state
                      'inputResponses (hasheq 'answer (hasheq 'action "accept" 'content (hasheq 'ok #t))))
              (hasheq 'name "work"))
          #:capabilities (hasheq 'elicitation (hasheq))))
      (lambda ()
        (client-close! client)
        (unless (sync/timeout 5 process) (subprocess-kill process #t))
        (subprocess-wait process)
        (define stderr (port->string err))
        (close-input-port err)
        (check-equal? (subprocess-status process) 0 stderr))))
  (define (pending build-id)
    (define response (call build-id))
    (define result (hash-ref response 'result))
    (check-equal? (hash-ref result 'resultType) "input_required")
    (hash-ref result 'requestState))
  (dynamic-wind void
    (lambda ()
      (write-helper "before")
      (call-with-output-file application
        (lambda (out)
          (display "#lang mcp\n(require \"helper.rkt\")\n(server #:name \"loaded\" #:version \"1\")\n" out)
          (write
            `(workflow (work) #:version "1"
               (checkpoint [saved String] (helper))
               (await-input [answer Any]
                 (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
               (text-result
                 (begin
                   (call-with-output-file ,(path->string completed) #:exists 'append
                     (lambda (out) (displayln (helper) out)))
                   (helper)))) out)
          (newline out)))
      (define state (pending "explicit-test-runtime/1"))
      (define incompatible-runtime (call "explicit-test-runtime/2" state))
      (check-equal? (hash-ref (hash-ref incompatible-runtime 'error) 'code) -32603)
      (check-false (file-exists? completed))
      (define compatible (call "explicit-test-runtime/1" state))
      (check-equal? (hash-ref (hash-ref compatible 'result) 'resultType) "complete")
      (check-equal? (file->string completed) "before\n")
      (define still-pending (pending "explicit-test-runtime/1"))
      (write-helper "after")
      (define incompatible-helper (call "explicit-test-runtime/1" still-pending))
      (check-equal? (hash-ref (hash-ref incompatible-helper 'error) 'code) -32603)
      (check-equal? (file->string completed) "before\n")
      (define fresh (pending "explicit-test-runtime/1"))
      (define changed-result (call "explicit-test-runtime/1" fresh))
      (check-equal? (hash-ref (hash-ref changed-result 'result) 'resultType) "complete")
      (check-equal? (file->string completed) "before\nafter\n"))
    (lambda () (delete-directory/files directory))))
(check-loader-entry (list (find-executable-path "racket") cli))
(check-loader-entry (list (find-executable-path "raco") "mcp"))
