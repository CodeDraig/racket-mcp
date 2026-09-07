#lang racket/base
(require rackunit racket/file racket/list racket/async-channel mcp mcp/upstream)
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities
                                  (hasheq 'tools (hasheq) 'extensions (hash-ref caps 'extensions)))
          'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object"))))
          'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '())
          'prompts/list (hasheq 'prompts '())))
(define base (hasheq 'taskId "remote" 'status "working" 'createdAt "2026-09-07T18:00:00Z"
                     'lastUpdatedAt "2026-09-07T18:00:00Z" 'ttlMs 86400000))
(define form (hasheq 'method "elicitation/create" 'params
  (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq)))))
(define observed (hash-set* base 'resultType "complete" 'status "completed" 'result (text-result "observed completion")))
(define directory (make-temporary-file "mcp-upstream-task-retry-~a" 'directory))
(define (exercise path lose-again? operation)
  (define (open) (if path (open-sqlite-store path) (open-memory-store)))
  (define store (open))
  (define mutations '())
  (define entered (make-semaphore))
  (define release (make-semaphore))
  (define polls 0)
  (define reject-verification? #f)
  (define (peer method params)
    (when (and reject-verification? (equal? method "server/discover")) (error 'peer "verification unavailable"))
    (cond [(hash-ref snapshot (string->symbol method) #f) => values]
          [else
           (case (string->symbol method)
             [(tools/call) (hash-set base 'resultType "task")]
             [(tasks/get)
              (set! polls (add1 polls))
              (if (= (length mutations) 2) observed
                  (hash-set* base 'resultType "complete" 'status "input_required" 'inputRequests (hasheq 'input form)))]
             [(tasks/update tasks/cancel)
              (set! mutations (append mutations (list params)))
              (when (or (= (length mutations) 1) lose-again?) (error 'peer "lost mutation response"))
              (semaphore-post entered)
              (semaphore-wait release)
              (hasheq 'resultType "complete")]
             [else (error 'test "unexpected upstream method")])]))
  (define bridge (make-upstream-bridge #:identity "peer" #:version "1" #:credential-id (lambda (_) "account")))
  (define iface (make-upstream-interface snapshot peer #:bridge bridge))
  (define rt (make-runtime iface #:store store))
  (define (call method params) (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal "alice"))
  (define authorized 0)
  (define (retry id)
    (retry-upstream-task! bridge store snapshot peer id #:principal "alice" #:credential-id "account"
      #:authorize (lambda () (set! authorized (add1 authorized)))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (call "tools/call" (hasheq 'name "work")) 'taskId))
      (define params (hasheq 'taskId id))
      (define input (car (hash-keys (hash-ref (call "tasks/get" params) 'inputRequests))))
      (check-exn #rx"requires recovery"
        (lambda () (call operation (if (equal? operation "tasks/cancel") params
                         (hash-set params 'inputResponses (hasheq input (hasheq 'action "decline")))))))
      (define failed (call "tasks/get" params))
      (define count-before (length (list-instances store)))
      (check-exn #rx"denied"
        (lambda () (retry-upstream-task! bridge store snapshot peer id #:principal "alice" #:credential-id "account"
                     #:authorize (lambda () (error 'operator "denied")))))
      (check-equal? (length (list-instances store)) count-before)
      (define before-auth authorized)
      (check-exn #rx"own its storage" (lambda () (store-transaction store (lambda () (retry id)))))
      (check-equal? authorized before-auth)
      (set! reject-verification? #t)
      (check-exn #rx"verification unavailable" (lambda () (retry id)))
      (define event (findf (lambda (event) (equal? (hash-ref event 'kind #f) "upstream-task-replacement")) (instance-events store id)))
      (check-equal? (hash-ref event 'action) "retry")
      (define new-id (hash-ref event 'taskId))
      (check-not-equal? new-id id)
      (check-equal? (length mutations) 1)
      (check-equal? (hash-ref (call "tasks/get" (hasheq 'taskId new-id)) 'status) "working")
      (check-equal? polls 1)
      (when path
        (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
        (set! store (open)) (set! rt (make-runtime iface #:store store)))
      (set! reject-verification? #f)
      (define receipt
        (if lose-again?
            (begin (check-exn #rx"requires recovery" (lambda () (retry id))) (retry id))
            (let ([results (make-async-channel)])
              (parameterize ([current-custodian (runtime-custodian rt)])
                (thread (lambda ()
                  (with-handlers ([(lambda (_) #t) (lambda (e) (async-channel-put results e))])
                    (async-channel-put results (retry id))))))
              (check-not-false (sync/timeout 3 entered))
              ;; Another operator gets the recorded handle while the one
              ;; authorized resend is still active, without a second send.
              (define concurrent (retry id))
              (semaphore-post release)
              (check-equal? (sync/timeout 3 results) concurrent)
              concurrent)))
      (check-equal? (hash-ref receipt 'taskId) new-id)
      (check-equal? (length mutations) 2)
      (check-equal? (car mutations) (cadr mutations))
      (check-equal? (retry id) receipt)
      (check-equal? (length mutations) 2)
      (check-equal? (call "tasks/get" params) failed)
      (define current (call "tasks/get" (hasheq 'taskId new-id)))
      (check-equal? (hash-ref current 'status) (if lose-again? "failed" "completed"))
      (check-equal? (call "tasks/get" (hasheq 'taskId new-id)) current)
      (check-exn #rx"Conflicting" (lambda () (recover-upstream-task! bridge store snapshot id #:principal "alice" #:credential-id "account" #:outcome observed)))
      (check-equal? (length (list-instances store)) (add1 count-before)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
(dynamic-wind void
  (lambda ()
    (for* ([operation '("tasks/update" "tasks/cancel")] [lost? '(#f #t)])
      (exercise #f lost? operation)
      (exercise (build-path directory (string-append (if (equal? operation "tasks/update") "update-" "cancel-")
                                                      (if lost? "lost.sqlite" "success.sqlite"))) lost? operation)))
  (lambda () (delete-directory/files directory)))
