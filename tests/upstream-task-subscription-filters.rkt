#lang racket/base
;; These protocol fixtures own downstream listener lifetimes explicitly.
;; Default loss propagation is covered by upstream-resource-loss/upstream-task-loss.
(require rackunit racket/list racket/async-channel mcp mcp/upstream
         mcp/upstream-subscription mcp/stdio)
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28")
    'capabilities (hasheq 'tools (hasheq) 'extensions (hash-ref caps 'extensions)))
    'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object")
      'outputSchema (object-schema (hasheq 'value Integer) #:required '("value")))))
    'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '())
    'prompts/list (hasheq 'prompts '())))
(define base (hasheq 'status "working" 'createdAt "2026-09-07T00:00:00Z"
  'lastUpdatedAt "2026-09-07T00:00:00Z" 'ttlMs 60000))
(define (tagged value [tag 77]) (hash-set value '_meta (hasheq 'io.modelcontextprotocol/subscriptionId tag)))
(define (notice method value [tag 77]) (hasheq 'jsonrpc "2.0" 'method method 'params (tagged value tag)))
(define (ack filter [tag 77]) (notice "notifications/subscriptions/acknowledged" (hasheq 'notifications filter) tag))
(define update (notice "notifications/tasks" (hash-set base 'taskId "a")))
(define complete (hasheq 'jsonrpc "2.0" 'id 77 'result (tagged (hasheq 'resultType "complete"))))
(define store (open-memory-store))
(define clock (make-manual-clock #:seconds 100))
(define remote-ids '("a" "b" "a"))
(define (peer method params)
  (cond [(hash-ref snapshot (string->symbol method) #f) => values]
        [(equal? method "tools/call")
         (define id (car remote-ids)) (set! remote-ids (cdr remote-ids))
         (hash-set* base 'resultType "task" 'taskId id)]
        [else (error 'test "unexpected upstream task polling or mutation")]))
(define source (make-upstream-interface snapshot peer #:bridge
  (make-upstream-bridge #:identity "filters" #:version "1" #:credential-id (lambda (_) "credential"))))
(define rt (make-runtime source #:store store #:clock clock))
(define ids (for/list ([i (in-range 3)])
  (hash-ref (dispatch rt "tools/call" (hasheq 'name "work" '_meta (request-meta #:capabilities caps)) #:principal "owner") 'taskId)))
(define events (make-async-channel))
(define (revisions) (map (lambda (id) (stored-instance-revision (load-instance store id))) ids))
(define (run messages proc #:outcome [outcome complete])
  (define cancelled 0)
  (define queue (make-async-channel))
  (for ([message (in-list messages)]) (async-channel-put queue message))
  (define handle (request-handle 77 (make-semaphore 1) (box outcome)
    (lambda () (set! cancelled (add1 cancelled))) queue))
  (define (request method params)
    (cond [(equal? method "subscriptions/listen")
           (check-equal? (sort (hash-ref (hash-ref params 'notifications) 'taskIds) string<?) '("a" "b")) handle]
          [else (request-handle 1 (make-semaphore 1) (box (hasheq 'result (hash-ref snapshot (string->symbol method))))
                  void (make-async-channel))]))
  (dynamic-wind void
    (lambda () (call-with-upstream-task-subscription #:propagate-loss? #f rt snapshot request ids proc #:principal "owner" #:capabilities caps))
    (lambda () (check-true (> cancelled 0)))))
(define accepted (ack (hasheq 'taskIds '("a"))))
(dynamic-wind void
  (lambda ()
    (parameterize ([current-custodian (runtime-custodian rt)])
      (thread (lambda () (dispatch rt "subscriptions/listen"
        (hasheq '_meta (request-meta #:capabilities caps) 'notifications (hasheq 'taskIds ids))
        #:principal "owner" #:id 99 #:notify (lambda (event) (async-channel-put events event))))))
    (check-equal? (hash-ref (sync/timeout 2 events) 'method) "notifications/subscriptions/acknowledged")
    ;; Setup rejection must not invoke the consumer or touch any stored task.
    (for ([messages (in-list
      (list (list (ack (hasheq 'taskIds '("foreign"))))
            (list (ack (hasheq 'taskIds '("a")) 78))
            (list (ack (hasheq 'resourceSubscriptions '("a"))))
            (list (ack (hasheq 'taskIds '(1))))
            (list update accepted) '()))])
      (define before (revisions))
      (define called? #f)
      (check-exn exn:fail? (lambda () (run messages (lambda (_) (set! called? #t)))))
      (check-false called?)
      (check-equal? (revisions) before)
      (check-false (sync/timeout 0 events)))
    ;; Once acknowledged, malformed/unaccepted updates end the event, without writes.
    (for ([bad (in-list
      (list (notice "notifications/tasks" (hash-set base 'taskId "b"))
            (notice "notifications/tasks" (hash-set base 'taskId "foreign"))
            (notice "notifications/tasks" (hash-set base 'taskId "a") 78)
            (notice "notifications/resources/updated" (hasheq 'taskId "a"))
            (notice "notifications/tasks" (hasheq 'taskId "a"))
            (notice "notifications/tasks" (hash-set* base 'taskId "a" 'status "completed"
              'result (hasheq 'resultType "complete" 'content '() 'structuredContent (hasheq 'value "invalid"))))))])
      (define before (revisions))
      (define outcome (run (list accepted bad) (lambda (subscription) (sync/timeout 2 subscription))))
      (check-true (exn:fail? outcome))
      (check-equal? (revisions) before)
      (check-false (sync/timeout 0 events)))
    ;; Empty acceptance is legal; it cannot authorize a subsequent task update.
    (for ([filter (in-list (list (hasheq) (hasheq 'taskIds '())))])
      (define before (revisions))
      (check-equal? (run (list (ack filter)) (lambda (subscription)
        (check-equal? (upstream-task-subscription-accepted subscription) '())
        (sync/timeout 2 subscription))) complete)
      (check-true (exn:fail? (run (list (ack filter) update) (lambda (subscription) (sync/timeout 2 subscription)))))
      (check-equal? (revisions) before)
      (check-false (sync/timeout 0 events)))
    ;; Accepted remote a maps to two distinct local handles, in requested order.
    (define before (revisions))
    (check-equal? (run (list accepted update update) (lambda (subscription)
      (check-equal? (upstream-task-subscription-accepted subscription) (list (first ids) (third ids)))
      (sync/timeout 2 subscription))) complete)
    (check-equal? (revisions) (list (add1 (first before)) (second before) (add1 (third before))))
    (define delivered (for/list ([i (in-range 2)]) (hash-ref (hash-ref (sync/timeout 2 events) 'params) 'taskId)))
    (check-equal? delivered (list (first ids) (third ids)))
    (check-false (sync/timeout 0 events))
    ;; Expired handles fail before even discovery, with no silent re-listen.
    (manual-clock-advance! clock 61)
    (define requests 0)
    (check-exn exn:fail? (lambda ()
      (call-with-upstream-task-subscription #:propagate-loss? #f rt snapshot (lambda (_m _p) (set! requests (add1 requests))) ids void
        #:principal "owner" #:capabilities caps)))
    (check-equal? requests 0))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
