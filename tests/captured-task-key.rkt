#lang racket/base
(require rackunit racket/file mcp)
(define directory (make-temporary-file "mcp-captured-task-key-~a" 'directory))
(define application (build-path directory "application.rkt"))
(define unexpected (build-path directory "unexpected.rkt"))
(define marker (build-path directory "loaded.txt"))
(define store #f)
(define rt #f)
(dynamic-wind void
  (lambda ()
    (call-with-output-file unexpected
      (lambda (out)
        (displayln "#lang racket/base" out)
        (write `(call-with-output-file ,(path->string marker) (lambda (out) (display "loaded" out))) out)
        (newline out)
        (displayln "(provide key) (define key \"same\")" out)))
    (call-with-output-file application
      (lambda (out)
        (displayln "#lang mcp" out)
        (write `(workflow (work) #:version "1" #:execution task
                  #:key (lambda (_) (dynamic-require '(file ,(path->string unexpected)) 'key))
                  (text-result "done")) out)
        (newline out)))
    (define interface (load-interface application #:runtime-build-id "explicit-task-key-fixture/1"))
    (set! store (open-memory-store))
    (set! rt (make-runtime interface #:store store))
    (check-exn #rx"not loaded in the sealed executable"
      (lambda ()
        (dispatch rt "tools/call"
          (hasheq '_meta (request-meta #:capabilities (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
                  'name "work") #:principal "alice")))
    (check-false (file-exists? marker))
    (check-equal? (list-instances store) '()))
  (lambda ()
    (when rt (custodian-shutdown-all (runtime-custodian rt)))
    (when store (close-store! store))
    (delete-directory/files directory)))
