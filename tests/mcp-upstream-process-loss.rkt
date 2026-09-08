#lang racket/base
(require rackunit racket/file racket/list racket/port racket/runtime-path racket/async-channel mcp mcp/upstream mcp/http (only-in web-server/http header-field header-value))
(define-runtime-path self "mcp-upstream-process-loss.rkt")
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(module+ main
  (define argv (current-command-line-arguments))
  (define directory (vector-ref argv 0))
  (define mode (vector-ref argv 1))
  (define control (vector-ref argv 2))
  (cond
    [(equal? mode "remote")
     (workflow (work) #:version "1" #:execution task
       (await-input [answer Any] (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
       (text-result "finished"))
     (define store (open-sqlite-store (build-path directory "remote.sqlite")))
     (define rt (make-runtime (make-interface #:tools (list work)) #:store store))
     (define confirmation (make-async-channel))
     (define stop (serve-http rt #:port 0 #:confirmation confirmation
       #:authenticate (lambda (headers)
         (define method (for/first ([h (in-list headers)]
           #:when (string-ci=? (bytes->string/utf-8 (header-field h)) "Mcp-Method"))
           (bytes->string/utf-8 (header-value h))))
         (when (member method '("tools/call" "tasks/update" "tasks/cancel"))
           (call-with-output-file (build-path directory "remote-calls") #:exists 'append
             (lambda (out) (displayln method out))))
         'local)))
     (define port (sync confirmation)) (when (exn? port) (raise port))
     (displayln (format "http://127.0.0.1:~a/mcp" port)) (flush-output)
     (read-line)
     (stop) (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)]
    [else
     (define client (make-http-client (vector-ref argv 3)))
     (define (peer method params)
       (define reply (http-client-call client method params #:capabilities caps))
       (when (hash-has-key? reply 'error) (error 'peer "~s" reply))
       (when (and (equal? mode "start") (equal? method control))
         ;; Peer acknowledgement has arrived; the local command intent has not
         ;; yet been replaced by its recorded acknowledgement.
         (displayln "ready") (flush-output) (sync never-evt))
       (hash-ref reply 'result))
     (define iface (make-upstream-interface (capture-snapshot peer) peer #:bridge
       (make-upstream-bridge #:identity "real-peer" #:version "1" #:credential-id (lambda (_) "remote-owner"))))
     (define store (open-sqlite-store (build-path directory "local.sqlite")))
     (define rt (make-runtime iface #:store store))
     (define (call method params)
       (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal "alice"))
     (define id-path (build-path directory "local-id"))
     (define id
       (if (equal? mode "start")
           (let ([id (hash-ref (call "tools/call" (hasheq 'name "work")) 'taskId)])
             (display-to-file id id-path) id)
           (file->string id-path)))
     (define params (hasheq 'taskId id))
     (cond
       [(equal? mode "start")
        (define detail
          (let loop ([left 200])
            (define result (call "tasks/get" params))
            (cond [(equal? (hash-ref result 'status) "input_required") result]
                  [(zero? left) (error 'test "upstream input did not arrive")]
                  [else (sleep 0.01) (loop (sub1 left))])))
        (call control (if (equal? control "tasks/update")
          (hash-set params 'inputResponses (for/hasheq ([id (in-hash-keys (hash-ref detail 'inputRequests))])
                                            (values id (hasheq 'action "decline")))) params))]
       [else
        (define failed (call "tasks/get" params))
        (void (call control params))
        (unless (equal? (call "tasks/get" params) failed) (error 'test "terminal result changed"))
        (write-json failed) (newline)])
     (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)]))
(module+ test
  (define root (make-temporary-file "mcp-upstream-process-loss-~a" 'directory))
  (define (spawn directory mode control [url ""])
    (subprocess #f #f #f (find-executable-path "racket") self directory mode control url))
  (define (cleanup p out in err)
    (close-output-port in)
    (unless (sync/timeout 5 p) (subprocess-kill p #t))
    (subprocess-wait p) (close-input-port out) (close-input-port err))
  (dynamic-wind void
    (lambda ()
      (for ([control '("tasks/update" "tasks/cancel")])
        (test-case control
          (define directory (build-path root (if (equal? control "tasks/update") "update" "cancel")))
          (make-directory directory)
          (define-values (remote remote-out remote-in remote-err) (spawn directory "remote" control))
          (dynamic-wind void
            (lambda ()
              (unless (sync/timeout 15 remote-out) (error 'test "remote startup timed out"))
              (define url (read-line remote-out)) (check-true (string? url))
              (define-values (p out in err) (spawn directory "start" control url))
              (dynamic-wind void
                (lambda ()
                  (unless (sync/timeout 15 out) (error 'test "local command boundary timed out"))
                  (check-equal? (read-line out) "ready")
                  (check-equal? (subprocess-status p) 'running))
                (lambda () (subprocess-kill p #t) (cleanup p out in err)))
              (define store (open-sqlite-store (build-path directory "local.sqlite")))
              (define row (load-instance store (file->string (build-path directory "local-id"))))
              (check-equal? (hash-ref (hash-ref (stored-instance-state row) 'command) 'status) "intent")
              (close-store! store)
              (define results
                (for/list ([i (in-range 2)])
                  (define-values (p out in err) (spawn directory "resume" control url))
                  (dynamic-wind void
                    (lambda ()
                      (unless (sync/timeout 15 p) (error 'test "resume timed out"))
                      (define stdout (port->string out))
                      (check-equal? (subprocess-status p) 0 (port->string err))
                      (string->json stdout))
                    (lambda () (cleanup p out in err)))))
              (check-equal? (car results) (cadr results))
              (check-equal? (hash-ref (car results) 'status) "failed")
              (check-regexp-match #rx"uncertain" (hash-ref (hash-ref (car results) 'error) 'message))
              (check-equal? (file->lines (build-path directory "remote-calls")) (list "tools/call" control)))
            (lambda () (cleanup remote remote-out remote-in remote-err))))))
    (lambda () (delete-directory/files root))))
