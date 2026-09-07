#lang racket/base
(require rackunit racket/file racket/port racket/runtime-path mcp/stdio mcp/storage)
(define-runtime-path cli "../mcp/cli.rkt")
(define directory (make-temporary-file "mcp-task-key-restart-~a" 'directory))
(define application (build-path directory "application.rkt"))
(define database (build-path directory "state.sqlite"))
(define marker (build-path directory "prefix.txt"))
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define (session proc)
  (define-values (process out in err)
    (subprocess #f #f #f (find-executable-path "racket") cli "--state" database "serve" application))
  (define client (make-stdio-client out in #:timeout 10))
  (dynamic-wind void
    (lambda () (proc (lambda (method params)
                      (define reply (client-call client method params #:capabilities caps))
                      (when (hash-has-key? reply 'error) (error 'test "wire failure: ~s" reply))
                      (hash-ref reply 'result))))
    (lambda ()
      (client-close! client)
      (unless (sync/timeout 5 process) (subprocess-kill process #t))
      (subprocess-wait process)
      (define stderr (port->string err))
      (close-input-port err)
      (check-equal? (subprocess-status process) 0 stderr))))
(define (await-status call id status)
  (let loop ([left 100])
    (define result (call "tasks/get" (hasheq 'taskId id)))
    (cond [(equal? (hash-ref result 'status) status) result]
          [(zero? left) (error 'test "did not reach ~a: ~s" status result)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
(dynamic-wind void
  (lambda ()
    (call-with-output-file application
      (lambda (out)
        (display "#lang mcp\n(server #:name \"prepared\" #:version \"1\")\n" out)
        (write
         `(workflow (work [key String]) #:version "1" #:execution task
            #:key (lambda (arguments) (hash-ref arguments 'key))
            (checkpoint [prefix String]
              (begin (call-with-output-file ,(path->string marker) #:exists 'append
                       (lambda (out) (displayln "once" out))) "Hello "))
            (await-input [finish Any]
              (hasheq 'mode "form" 'message "Finish?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
            (text-result (string-append prefix key))) out)
        (newline out)))
    (define retry (hasheq 'name "work" 'arguments (hasheq 'key "Ada")))
    (define created
      (session
       (lambda (call)
         (define task (call "tools/call" retry))
         (check-equal? (hash-ref task 'resultType) "task")
         (void (await-status call (hash-ref task 'taskId) "input_required"))
         task)))
    (define inspector (open-sqlite-store database))
    (check-equal? (length (list-instances inspector)) 2)
    (close-store! inspector)
    (session
     (lambda (call)
       (check-equal? (call "tools/call" retry) created)
       (define id (hash-ref created 'taskId))
       (define pending (await-status call id "input_required"))
       (check-true (hash-has-key? (hash-ref pending 'inputRequests) 'finish))
       (check-equal? (call "tasks/update" (hasheq 'taskId id 'inputResponses
                                                 (hasheq 'finish (hasheq 'action "accept" 'content (hasheq 'ok #t)))))
                     (hasheq 'resultType "complete"))
       (define final (await-status call id "completed"))
       (check-equal? (hash-ref (hash-ref final 'result) 'content)
                     (list (hasheq 'type "text" 'text "Hello Ada")))))
    (session (lambda (call) (check-equal? (call "tools/call" retry) created)))
    (check-equal? (file->string marker) "once\n"))
  (lambda () (delete-directory/files directory)))
