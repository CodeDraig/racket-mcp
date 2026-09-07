#lang racket/base
(require rackunit racket/file racket/port racket/runtime-path mcp/stdio mcp/storage)
(define-runtime-path cli "../mcp/cli.rkt")
(define directory (make-temporary-file "mcp-upstream-task-restart-~a" 'directory))
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
(define remote-database (build-path directory "remote.sqlite"))
(define remote-calls (build-path directory "remote-calls.txt"))
(dynamic-wind void
  (lambda ()
    (call-with-output-file application
      (lambda (out)
        (displayln "#lang racket/base" out)
        (for ([form (in-list
          `((require mcp mcp/upstream)
            (workflow (work) #:version "1" #:execution task
              (checkpoint [prefix String]
                (begin (call-with-output-file ,(path->string marker) #:exists 'append
                         (lambda (out) (displayln "once" out))) "Hello "))
              (await-input [name Any]
                (hasheq 'mode "form" 'message "Name?" 'requestedSchema (object-schema (hasheq 'name String))))
              (text-result (string-append prefix (hash-ref (hash-ref name 'content) 'name))))
            (define remote-store (open-sqlite-store ,(path->string remote-database)))
            (define remote (make-runtime (make-interface #:tools (list work)) #:store remote-store))
            (define (peer method params)
              (when (equal? method "tools/call")
                (call-with-output-file ,(path->string remote-calls) #:exists 'append (lambda (out) (displayln "call" out))))
              (dispatch remote method (hash-set params '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))))
                        #:principal "remote-owner"))
            (define imported
              (make-upstream-interface (capture-snapshot peer) peer
                #:bridge (make-upstream-bridge #:identity "remote" #:version "1" #:credential-id (lambda (_) "remote-owner"))))
            (define mcp-interface
              (make-interface #:server (server-descriptor "local" "1" #f) #:tools (interface-descriptor-tools imported)))
            (provide mcp-interface)))])
          (write form out) (newline out))))
    (define (wait-status call id status)
      (let loop ([left 100])
        (define result (call "tasks/get" (hasheq 'taskId id)))
        (cond [(equal? (hash-ref result 'status) status) result]
              [(zero? left) (error 'test "task did not reach ~a: ~s" status result)]
              [else (sync (alarm-evt (+ (current-inexact-milliseconds) 20))) (loop (sub1 left))])))
    (define first
      (session (lambda (call)
        (define created (call "tools/call" (hasheq 'name "work")))
        (check-equal? (hash-ref created 'resultType) "task")
        (wait-status call (hash-ref created 'taskId) "input_required"))))
    (define id (hash-ref first 'taskId))
    (define local-input (car (hash-keys (hash-ref first 'inputRequests))))
    (check-not-equal? local-input 'name)
    (define inspector (open-sqlite-store database))
    (define instance (load-instance inspector id))
    (check-not-equal? id (hash-ref (stored-instance-state instance) 'remoteId))
    (close-store! inspector)
    (define final
      (session (lambda (call)
        (void (call "tasks/update" (hasheq 'taskId id 'inputResponses
          (hasheq local-input (hasheq 'action "accept" 'content (hasheq 'name "Ada"))))))
        (wait-status call id "completed"))))
    (check-equal? (hash-ref (hash-ref final 'result) 'content) (list (hasheq 'type "text" 'text "Hello Ada")))
    (check-equal? (session (lambda (call) (call "tasks/get" (hasheq 'taskId id)))) final)
    (check-equal? (file->string marker) "once\n")
    (check-equal? (file->string remote-calls) "call\n"))
  (lambda () (delete-directory/files directory)))
