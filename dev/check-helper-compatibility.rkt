#lang racket/base
(require racket/file racket/port racket/string mcp/json)
;; Release probe: changed imported code must not resume an old checkpoint. This
;; is deliberately not an expected-failure test in the passing native suite.
(define worker-source
  #<<SOURCE
#lang racket/base
(require mcp "helper.rkt")
(workflow (work) #:version "1"
  (checkpoint [saved String] (helper))
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Continue?"
            'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (text-result (helper)))
(define args (current-command-line-arguments))
(define store (open-sqlite-store (vector-ref args 0)))
(dynamic-wind void
  (lambda ()
    (with-handlers ([exn:fail:recovery?
                    (lambda (failure)
                      (write-json (hasheq 'rejected #t 'message (exn-message failure)))
                      (newline))])
      (write-json
        (run-workflow (tool-descriptor-workflow work) store (hasheq) #:principal "alice"
          #:state (and (= (vector-length args) 2) (vector-ref args 1))
          #:responses (if (= (vector-length args) 2)
                          (hasheq 'answer (hasheq 'action "accept" 'content (hasheq 'ok #t)))
                          (hasheq))))
      (newline)))
  (lambda () (close-store! store)))
SOURCE
  )
(module+ main
  (define directory (make-temporary-file "mcp-helper-compatibility-~a" 'directory))
  (define worker (build-path directory "worker.rkt"))
  (define helper (build-path directory "helper.rkt"))
  (define database (build-path directory "state.sqlite"))
  (define (write-helper value)
    (call-with-output-file helper #:exists 'truncate
      (lambda (out)
        (displayln "#lang racket/base" out)
        (write '(provide helper) out) (newline out)
        (write `(define (helper) ,value) out) (newline out))))
  (define (run . arguments)
    (define-values (process out in err)
      (apply subprocess #f #f #f (find-executable-path "racket") worker database arguments))
    (close-output-port in)
    (define watchdog
      (thread (lambda () (unless (sync/timeout 30 process) (subprocess-kill process #t)))))
    (define stdout (port->string out))
    (define stderr (port->string err))
    (subprocess-wait process) (thread-wait watchdog)
    (close-input-port out) (close-input-port err)
    (unless (zero? (subprocess-status process))
      (error 'helper-compatibility "child failed: ~a" stderr))
    (string->json (string-trim stdout)))
  (dynamic-wind void
    (lambda ()
      (call-with-output-file worker (lambda (out) (display worker-source out)))
      (write-helper "before")
      (define initial (run))
      (unless (equal? (hash-ref initial 'resultType #f) "input_required")
        (error 'helper-compatibility "initial execution did not checkpoint and suspend"))
      (write-helper "after")
      (define resumed (run (hash-ref initial 'requestState)))
      (unless (hash-ref resumed 'rejected #f)
        (error 'helper-compatibility "changed imported helper resumed saved execution: ~a" resumed))
      (displayln "Changed imported helper rejected before continuation execution."))
    (lambda () (delete-directory/files directory))))
