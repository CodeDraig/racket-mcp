#lang racket/base
(require racket/file racket/list mcp mcp/tasks)
(workflow (restartable) #:version "1" #:execution task
  (checkpoint [saved Integer] 42)
  (perform [mutation Integer] #:adapter effect #:policy idempotent saved)
  (text-result (number->string mutation)))
(module+ main
  (define args (current-command-line-arguments))
  (define database (vector-ref args 0))
  (define marker (vector-ref args 1))
  (define mode (vector-ref args 2))
  (define store (open-sqlite-store database))
  (define signal-output (current-output-port))
  (define adapters
    (hasheq 'effect
            (effect-adapter 'idempotent
              (lambda (value key connection)
                (displayln "effect diagnostic")
                (define previous (if (file-exists? marker) (file->lines marker) '()))
                (unless (or (null? previous) (equal? previous (list key))) (error 'adapter "changed effect key"))
                (when (null? previous) (display-to-file (string-append key "\n") marker))
                (display-to-file "attempt\n" (string-append marker ".attempts") #:exists 'append)
                (when (equal? mode "start") (displayln "ready" signal-output) (flush-output signal-output) (sync never-evt))
                value))))
  (define rt
    (make-runtime (make-interface #:tools (list restartable)) #:store store #:adapters adapters
                  #:recover-tasks? (not (equal? mode "probe"))
                  #:authorize (lambda (principal method params) (not (equal? mode "deny")))))
  (cond
    [(equal? mode "start")
     (void (start-workflow-task (tool-descriptor-workflow restartable) store (hasheq) "alice"
                               #:adapters adapters #:custodian (runtime-custodian rt)))
     (sync never-evt)]
    [else
     (when (equal? mode "probe") (for-each sync (recover-runtime-tasks! rt)))
     (define instance (findf (lambda (i) (hash-has-key? (stored-instance-state i) 'task)) (list-instances store)))
     (let loop ([remaining 300])
       (define task (get-task store (stored-instance-handle instance) "alice"))
       (cond [(or (equal? mode "probe") (member (hash-ref task 'status) '("completed" "failed")))
              (displayln (json->string task))]
             [(zero? remaining) (error 'test "recovery timed out")]
             [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 remaining))]))])
  (custodian-shutdown-all (runtime-custodian rt))
  (close-store! store))
