#lang racket/base
;; An application-owned fixture: the harness never reaches into its runtime.
(require db racket/file racket/async-channel mcp mcp/authorization mcp/stdio mcp/http)
(module+ main
  (define argv (current-command-line-arguments))
  (define directory (vector-ref argv 0))
  (define policy (string->symbol (vector-ref argv 1)))
  (define boundary (vector-ref argv 2))
  (define store (open-sqlite-store (build-path directory "state.sqlite")))
  (define external (sqlite3-connect #:database (build-path directory "application.sqlite") #:mode 'create))
  (define connection (if (eq? policy 'transactional) (state-store-connection store) external))
  (query-exec connection "CREATE TABLE IF NOT EXISTS mutations (effect_key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
  (define (pause-at where)
    (when (and (equal? where boundary) (not (file-exists? (build-path directory "release"))))
      (display-to-file where (build-path directory "ready") #:exists 'replace)
      (sync never-evt)))
  (define flow
    (make-workflow "mutate" "1" "effect-crash-fixture-v1"
      (list
        (workflow-stage 'saved 'checkpoint Integer
          (lambda (_)
            (display-to-file "checkpoint\n" (build-path directory "checkpoints") #:exists 'append) 7) #f #f)
        (workflow-stage 'answer 'input Any
          (lambda (_) (hasheq 'mode "form" 'message "Proceed?"
                              'requestedSchema (object-schema (hasheq 'ok Boolean)))) #f #f)
        (workflow-stage 'written 'effect Integer (lambda (env) (hash-ref env 'saved)) 'write policy)
        (workflow-stage 'done 'complete Any
          (lambda (env)
            (pause-at "recorded")
            (structured-result (hasheq 'value (hash-ref env 'written)))) #f #f))))
  (define operation
    (make-tool "mutate" '()
      (lambda (arguments)
        (run-workflow flow (current-workflow-store) arguments
          #:principal (principal-key (request-context-principal (current-request-context)))
          #:state (current-workflow-state) #:responses (current-workflow-responses)
          #:adapters (current-workflow-adapters))) #:workflow flow))
  (define rt
    (make-runtime (make-interface #:tools (list operation)) #:store store
      #:adapters
      (hasheq 'write (effect-adapter policy
        (lambda (input key tx)
          (display-to-file (string-append key "\n") (build-path directory "attempts") #:exists 'append)
          (pause-at "before")
          (query-exec (or tx external)
            (if (eq? policy 'idempotent)
                "INSERT OR IGNORE INTO mutations VALUES (?, ?)"
                "INSERT INTO mutations VALUES (?, ?)") key input)
          (pause-at "after")
          input)))))
  (if (equal? (vector-ref argv 3) "http")
      (let ([confirmation (make-async-channel)])
        (serve-http rt #:port 0 #:confirmation confirmation #:keepalive-seconds 0.05)
        (define port (sync confirmation))
        (when (exn? port) (raise port))
        (printf "http://127.0.0.1:~a/mcp\n" port)
        (flush-output)
        (sync never-evt))
      (serve-stdio rt)))
