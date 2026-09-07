#lang racket/base
(require rackunit racket/file mcp mcp/upstream)
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
(define directory (make-temporary-file "mcp-upstream-task-repair-~a" 'directory))
(define (exercise path)
  (define (open) (if path (open-sqlite-store path) (open-memory-store)))
  (define store (open))
  (define calls 0)
  (define (peer method params)
    (cond [(hash-ref snapshot (string->symbol method) #f) => values]
          [else
           (set! calls (add1 calls))
           (case (string->symbol method)
             [(tools/call) (hash-set base 'resultType "task")]
             [(tasks/get) (hash-set* base 'resultType "complete" 'status "input_required" 'inputRequests (hasheq 'input form))]
             [(tasks/update) (error 'peer "connection lost after mutation")]
             [else (error 'test "unexpected upstream request")])]))
  (define bridge (make-upstream-bridge #:identity "peer" #:version "1" #:credential-id (lambda (_) "account")))
  (define iface (make-upstream-interface snapshot peer #:bridge bridge))
  (define rt (make-runtime iface #:store store))
  (define (call method params) (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal "alice"))
  (define authorized 0)
  (define (repair id [outcome observed] [principal "alice"] [credential "account"] [pin snapshot])
    (recover-upstream-task! bridge store pin id #:principal principal #:credential-id credential #:outcome outcome
      #:authorize (lambda () (set! authorized (add1 authorized)))))
  (dynamic-wind void
    (lambda ()
      (define created (call "tools/call" (hasheq 'name "work")))
      (define id (hash-ref created 'taskId))
      (define params (hasheq 'taskId id))
      (check-exn #rx"no uncertain" (lambda () (repair id)))
      (define detail (call "tasks/get" params))
      (define input (car (hash-keys (hash-ref detail 'inputRequests))))
      (check-exn #rx"requires recovery"
        (lambda () (call "tasks/update" (hash-set params 'inputResponses (hasheq input (hasheq 'action "decline"))))))
      (define failed (call "tasks/get" params))
      (check-equal? (hash-ref failed 'status) "failed")
      (check-exn exn:fail? (lambda () (repair id observed "bob")))
      (check-exn exn:fail? (lambda () (repair id observed "alice" "another-account")))
      (check-exn exn:fail? (lambda () (repair id observed "alice" "account" (hash-set snapshot 'changed #t))))
      (check-exn #rx"another upstream task" (lambda () (repair id (hash-set observed 'taskId "foreign"))))
      (check-exn #rx"observed detailed" (lambda () (repair id (hasheq))))
      (define count-before (length (list-instances store)))
      (check-exn #rx"denied"
        (lambda () (recover-upstream-task! bridge store snapshot id #:principal "alice" #:credential-id "account"
                     #:outcome observed #:authorize (lambda () (error 'operator "denied")))))
      (check-equal? (length (list-instances store)) count-before)
      (define before-authorized authorized)
      (check-exn #rx"own its storage"
        (lambda () (store-transaction store (lambda () (repair id)))))
      (check-equal? authorized before-authorized)
      (define receipt (repair id))
      (define new-id (hash-ref receipt 'taskId))
      (check-not-equal? id new-id)
      (check-equal? (hash-ref receipt 'resultType) "task")
      (check-equal? (repair id) receipt)
      (check-equal? (repair id (hasheq 'jsonrpc "2.0" 'id 17 'result observed)) receipt)
      (check-exn #rx"Conflicting" (lambda () (repair id (hash-set observed 'result (text-result "different")))))
      (check-equal? (call "tasks/get" params) failed)
      (define completed (call "tasks/get" (hasheq 'taskId new-id)))
      (check-equal? (hash-ref completed 'status) "completed")
      (check-equal? (hash-ref completed 'result) (text-result "observed completion"))
      (check-equal? calls 3)
      (check-equal? (length (list-instances store)) (add1 count-before))
      (check-true (for/or ([event (in-list (instance-events store id))])
                    (equal? (hash-ref event 'kind #f) "upstream-task-replacement")))
      (check-true (for/or ([event (in-list (instance-events store new-id))])
                    (equal? (hash-ref event 'kind #f) "upstream-task-repair")))
      (when path
        (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
        (set! store (open)) (set! rt (make-runtime iface #:store store))
        (check-equal? (repair id) receipt)
        (check-equal? (call "tasks/get" (hasheq 'taskId new-id)) completed)
        (check-equal? (call "tasks/get" params) failed))
      (check-true (positive? authorized)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
(dynamic-wind void
  (lambda () (exercise #f) (exercise (build-path directory "state.sqlite")))
  (lambda () (delete-directory/files directory)))
