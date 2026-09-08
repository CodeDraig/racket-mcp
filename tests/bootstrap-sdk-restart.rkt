#lang racket/base
(require rackunit racket/file racket/path racket/runtime-path racket/system mcp/scenario)
(define-runtime-path sdk "../mcp")
(define-runtime-path metaschemas "../vendor/metaschemas")
(define directory (make-temporary-file "mcp-sdk-restart-~a" 'directory))
(define copy (build-path directory "mcp"))
(define application (build-path directory "application.rkt"))
(define database (build-path directory "state.sqlite"))
(define completed (build-path directory "completed.txt"))
(dynamic-wind void
  (lambda ()
    ;; Load actual SDK sources at one stable path in independent processes. Do
    ;; not copy bytecode from a potentially different installed Racket version.
    (for ([source (in-directory sdk)]
          #:when (and (file-exists? source)
                      (member (path-get-extension source) '(#".rkt" #".json"))))
      (define target (build-path copy (find-relative-path (simplify-path sdk) (simplify-path source))))
      (make-parent-directory* target)
      (copy-file source target))
    (make-directory* (build-path directory "vendor"))
    (copy-directory/files metaschemas (build-path directory "vendor" "metaschemas"))
    (call-with-output-file application
      (lambda (out)
        (displayln "#lang mcp\n(server #:name \"bootstrap\" #:version \"1\")" out)
        (fprintf out "(workflow (work) #:version \"1\"\n (await-input [answer Any] (hasheq 'mode \"form\" 'message \"Continue?\" 'requestedSchema (object-schema (hasheq 'ok Boolean))))\n (text-result (begin (display-to-file \"done\" ~s #:exists 'append) \"done\")))\n" (path->string completed))
        (displayln "(require racket/file)" out)))
    (define env (environment-variables-copy (current-environment-variables)))
    (environment-variables-set! env #"PLTCOLLECTS"
      (bytes-append (path->bytes directory)
                    (if (eq? (system-type 'os) 'windows) #";" #":")
                    (or (environment-variables-ref env #"PLTCOLLECTS") #"")))
    (define (build-sdk!)
      (define log (build-path directory "build.log"))
      (define success?
        (call-with-output-file log #:exists 'truncate
          (lambda (out)
            (parameterize ([current-environment-variables env]
                           [current-output-port out] [current-error-port out])
              (system* (find-executable-path "raco") "make"
                       (build-path copy "command.rkt") (build-path copy "lang.rkt")
                       (build-path copy "lang" "reader.rkt"))))))
      (unless success? (error 'bootstrap-sdk-restart "SDK build failed: ~a" (file->string log))))
    (build-sdk!)
    (call-with-scenario-process
      (list (find-executable-path "racket") "-l" "mcp/command" "--"
            "--runtime-build-id" "same-runtime-id" "--state" database "serve" application)
      (lambda (session)
        (define args (hasheq 'name "work"))
        (define (start) (hash-ref (scenario-process-call session "tools/call" args) 'result))
        (define (resume result)
          (scenario-process-call session "tools/call"
            (hash-set (hash-set args 'requestState (hash-ref result 'requestState))
                      'inputResponses (hasheq 'answer (hasheq 'action "decline")))))
        (define initial (start))
        (check-equal? (hash-ref initial 'resultType) "input_required")
        (scenario-process-restart! session)
        (define unchanged (resume initial))
        (unless (hash-has-key? unchanged 'result)
          (error 'bootstrap-sdk-restart "unchanged resume failed: ~s; stderr: ~a" unchanged (scenario-process-stderr session)))
        (check-equal? (hash-ref (hash-ref unchanged 'result) 'resultType) "complete")
        (check-equal? (file->string completed) "done")
        (define pending (start))
        (scenario-process-kill! session)
        (call-with-output-file (build-path copy "clock.rkt") #:exists 'append
          (lambda (out) (displayln "\n(provide changed-sdk-build)\n(define changed-sdk-build 'changed)" out)))
        (build-sdk!)
        (scenario-process-restart! session)
        (define rejected (resume pending))
        (check-true (hash-has-key? rejected 'error))
        (check-equal? (hash-ref (hash-ref rejected 'error) 'code) -32603)
        (check-equal? (file->string completed) "done")
        ;; The new SDK still executes a fresh workflow. Rejection must not be a
        ;; generic broken-server or handler failure caused by the fixture edit.
        (define fresh (start))
        (check-equal? (hash-ref fresh 'resultType) "input_required")
        (check-equal? (hash-ref (hash-ref (resume fresh) 'result) 'resultType) "complete")
        (check-equal? (file->string completed) "donedone"))
      #:environment env #:timeout 30 #:capabilities (hasheq 'elicitation (hasheq))))
  (lambda () (delete-directory/files directory)))
