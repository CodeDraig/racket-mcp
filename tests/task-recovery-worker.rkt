#lang racket/base
(require racket/file racket/list mcp mcp/tasks)
(workflow (repairable) #:version "1" #:execution task
  (checkpoint [saved Integer] 41)
  (perform [effect Integer] #:adapter write #:policy manual saved)
  (text-result (number->string effect)))
(module+ main
  (define args (current-command-line-arguments))
  (define store (open-sqlite-store (vector-ref args 0)))
  (define marker (vector-ref args 1))
  (define mode (vector-ref args 2))
  (define output (current-output-port))
  (define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
  (define (tasks)
    (filter (lambda (i) (hash-has-key? (stored-instance-state i) 'task)) (list-instances store)))
  (define (report)
    (for/list ([i (in-list (sort (tasks) string<? #:key stored-instance-handle))])
      (hasheq 'id (stored-instance-handle i)
              'revision (stored-instance-revision i)
              'parent (hash-ref (stored-instance-state i) 'replacesTask #f)
              'task (get-task store (stored-instance-handle i) "alice"))))
  (define (signal!) (displayln (json->string (report)) output) (flush-output output) (sync never-evt))
  (define (await-terminal id)
    (let loop ([left 500])
      (define task (get-task store id "alice"))
      (cond [(member (hash-ref task 'status) '("failed" "completed" "cancelled")) task]
            [(zero? left) (error 'worker "terminal task timeout")]
            [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
  (define authorization-count 0)
  (define rt
    (make-runtime (make-interface #:tools (list repairable)) #:store store
      #:recover-tasks? (equal? mode "resume")
      #:authorize
      (lambda (_principal method _params)
        (when (equal? method "tools/call")
          (set! authorization-count (add1 authorization-count))
          (when (and (equal? mode "replace-queue") (= authorization-count 2)) (signal!)))
        #t)
      #:adapters (hasheq 'write (effect-adapter 'manual
        (lambda (value key _connection)
          (display-to-file (string-append key "\n") marker #:exists 'append)
          (when (equal? mode "replace-effect") (signal!))
          (error 'effect "uncertain external effect"))))))
  (cond
    [(member mode '("prepared" "prepared-retry"))
     (define created (dispatch rt "tools/call"
       (hasheq '_meta (request-meta #:capabilities caps) 'name "repairable" 'arguments (hasheq)) #:principal "alice"))
     (define id (hash-ref created 'taskId))
     (await-terminal id)
     (define flow (hash-ref (stored-instance-state (load-instance store id)) 'workflow))
     (if (equal? mode "prepared-retry")
         (recover-workflow! store flow 'effect 'retry #:principal "alice")
         (recover-workflow! store flow 'effect 'outcome #:outcome 99 #:principal "alice"))
     (signal!)]
    [(equal? mode "resume")
     (for ([i (in-list (tasks))]) (await-terminal (stored-instance-handle i)))
     (displayln (json->string (report)) output)]
    [else
     (define original
       (if (equal? mode "repair-replacement")
           (findf (lambda (i) (hash-has-key? (stored-instance-state i) 'replacesTask)) (tasks))
           (findf (lambda (i) (not (hash-has-key? (stored-instance-state i) 'replacesTask))) (tasks))))
     (when (equal? mode "repair-replacement")
       (recover-workflow! store (hash-ref (stored-instance-state original) 'workflow) 'effect 'outcome #:outcome 99 #:principal "alice"))
     (define replacement (retry-runtime-task! rt (stored-instance-handle original) #:principal "alice" #:capabilities caps))
     (cond [(member mode '("replace-queue" "replace-effect")) (sync never-evt)]
           [else
            (await-terminal (hash-ref replacement 'taskId))
            (if (equal? mode "replace-complete") (signal!) (displayln (json->string (report)) output))])])
  (custodian-shutdown-all (runtime-custodian rt))
  (close-store! store))
