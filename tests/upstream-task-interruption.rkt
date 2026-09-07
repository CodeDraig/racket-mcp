#lang racket/base
(require rackunit racket/async-channel mcp mcp/upstream)
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities
                                  (hasheq 'tools (hasheq) 'extensions (hash-ref caps 'extensions)))
          'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object"))))
          'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '())
          'prompts/list (hasheq 'prompts '())))
(define base (hasheq 'taskId "remote" 'status "working" 'createdAt "2026-09-07T18:00:00Z"
                     'lastUpdatedAt "2026-09-07T18:00:00Z" 'ttlMs 100000))
(define form (hasheq 'method "elicitation/create" 'params
  (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq)))))
(for ([mode '(raise terminate failed)])
  (define store (open-memory-store))
  (define entered (make-semaphore))
  (define mutations 0)
  (define polls 0)
  (define (peer method params)
    (cond [(hash-ref snapshot (string->symbol method) #f) => values]
          [else
           (case (string->symbol method)
             [(tools/call) (hash-set base 'resultType "task")]
             [(tasks/get)
              (set! polls (add1 polls))
              (if (eq? mode 'failed)
                  (hash-set* base 'resultType "complete" 'status "failed" 'error (hasheq 'code -32603 'message "peer failed"))
                  (hash-set* base 'resultType "complete" 'status "input_required" 'inputRequests (hasheq 'input form)))]
             [(tasks/update)
              (set! mutations (add1 mutations))
              (semaphore-post entered)
              (if (eq? mode 'terminate) (sync never-evt) (error 'peer "lost response"))]
             [else (error 'peer "unexpected replay")])]))
  (define rt (make-runtime (make-upstream-interface snapshot peer
    #:bridge (make-upstream-bridge #:identity "peer" #:version "1" #:credential-id (lambda (_) "account"))) #:store store))
  (define (call method params) (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal "owner"))
  (dynamic-wind void
    (lambda ()
      (define created (call "tools/call" (hasheq 'name "work")))
      (define params (hasheq 'taskId (hash-ref created 'taskId)))
      (define detail (call "tasks/get" params))
      (cond [(eq? mode 'failed)
             (check-equal? (hash-ref detail 'status) "failed")
             (check-equal? (hash-ref (hash-ref detail 'error) 'message) "peer failed")]
            [else
             (define input (car (hash-keys (hash-ref detail 'inputRequests))))
             (define update (hash-set params 'inputResponses (hasheq input (hasheq 'action "decline"))))
             (if (eq? mode 'raise)
                 (check-exn #rx"requires recovery" (lambda () (call "tasks/update" update)))
                 (let ([worker (thread (lambda () (call "tasks/update" update)))])
                   (check-not-false (sync/timeout 2 entered))
                   (kill-thread worker)
                   (check-not-false (sync/timeout 2 worker))))
             (set! detail (call "tasks/get" params))
             (check-equal? (hash-ref detail 'status) "failed")
             (check-regexp-match #rx"uncertain" (hash-ref (hash-ref detail 'error) 'message))
             (void (call "tasks/update" update))
             (check-equal? mutations 1)])
      (check-equal? (call "tasks/get" params) detail)
      (void (call "tasks/cancel" params))
      (check-equal? polls 1))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
