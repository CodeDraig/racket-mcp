#lang racket/base
(require rackunit racket/async-channel mcp mcp/upstream mcp/authorization mcp/subscription)

(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities
    (hasheq 'tools (hasheq) 'extensions (hash-ref caps 'extensions)))
    'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object"))))
    'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '())
    'prompts/list (hasheq 'prompts '())))
(define base (hasheq 'taskId "remote-task" 'status "working" 'createdAt "2026-09-07T00:00:00Z"
                     'lastUpdatedAt "2026-09-07T00:00:00Z" 'ttlMs 60000))
(define (who scopes) (verified-principal "alice" "https://issuer.example" "https://api.example" scopes (+ (current-seconds) 600)))

(for* ([revocation? '(#f #t)] [policy '(callback scopes)])
  (test-case (format "upstream task subscription respects originating tool permission; revocation ~a, policy ~a" revocation? policy)
    (define operator (who '("execute")))
    (define subscriber (who '("read")))
    (define denied? (not revocation?))
    (define polls 0)
    (define (peer method params)
      (cond [(hash-ref snapshot (string->symbol method) #f) => values]
            [(equal? method "tools/call") (hash-set base 'resultType "task")]
            [else (set! polls (add1 polls)) (error 'peer "policy checks must not contact upstream")]))
    (define source (make-upstream-interface snapshot peer #:bridge
      (make-upstream-bridge #:identity "notification-policy" #:version "1" #:credential-id (lambda (_) "binding"))))
    (define store (open-memory-store))
    (define rt (make-runtime source #:store store #:authorize
      (lambda (principal method params)
        (when (equal? method "tools/call")
          (check-equal? (hash-ref params 'name) "work")
          (check-equal? (hash-ref params 'arguments) (hasheq 'input "saved")))
        (not (and (eq? policy 'callback) denied? (eq? principal subscriber) (equal? method "tools/call"))))
      #:required-scopes (lambda (method _params)
        (if (and (eq? policy 'scopes) denied? (equal? method "tools/call")) '("execute") '()))))
    (define events (make-async-channel))
    (define allowed-events (make-async-channel))
    (define release-delivery (make-semaphore))
    (define (call method params [principal operator])
      (dispatch rt method (hash-set params '_meta meta) #:principal principal))
    (define (listen id principal queue)
      (parameterize ([current-custodian (runtime-custodian rt)])
        (thread (lambda ()
          (with-handlers ([exn:fail:mcp? (lambda (e) (async-channel-put queue e))])
            (dispatch rt "subscriptions/listen"
              (hasheq '_meta meta 'notifications (hasheq 'taskIds (list id)))
              #:principal principal #:id (if (eq? principal subscriber) "restricted" "allowed")
              #:notify (lambda (event)
                (async-channel-put queue event)
                (when (and revocation? (eq? principal subscriber)
                           (equal? (hash-ref event 'method) "notifications/subscriptions/acknowledged"))
                  (semaphore-wait release-delivery)))))))))
    (dynamic-wind void
      (lambda ()
        (define receipt (call "tools/call" (hasheq 'name "work" 'arguments (hasheq 'input "saved"))))
        (define id (hash-ref receipt 'taskId))
        (when denied? (check-exn exn:fail:mcp? (lambda () (call "tasks/get" (hasheq 'taskId id) subscriber))))
        (listen id subscriber events)
        (define first (sync/timeout 5 events))
        (if revocation?
            (check-equal? (and (hash? first) (hash-ref first 'method)) "notifications/subscriptions/acknowledged")
            (check-true (exn:fail:mcp? first)))
        (listen id operator allowed-events)
        (check-equal? (hash-ref (sync/timeout 5 allowed-events) 'method) "notifications/subscriptions/acknowledged")
        (when revocation?
          ;; Queue a legitimate update while the subscriber is paused in its
          ;; acknowledgement callback, then revoke before delivery can run.
          (void (runtime-observe-upstream-task! rt id base #:principal operator #:capabilities caps))
          (check-equal? (hash-ref (hash-ref (sync/timeout 5 allowed-events) 'params) 'status) "working"))
        (set! denied? #t)
        (semaphore-post release-delivery)
        (check-exn exn:fail:mcp? (lambda () (call "tasks/get" (hasheq 'taskId id) subscriber)))
        (define completed (hash-set* base 'status "completed" 'result (text-result "private result")))
        (void (runtime-observe-upstream-task! rt id completed #:principal operator #:capabilities caps))
        (define allowed (sync/timeout 5 allowed-events))
        (check-equal? (and allowed (hash-ref (hash-ref allowed 'params) 'status)) "completed")
        (check-equal? (hash-ref (hash-ref (hash-ref allowed 'params) 'result) 'content)
                      (list (hasheq 'type "text" 'text "private result")))
        (check-false (sync/timeout 0.1 events))
        (check-equal? polls 0))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))))

(workflow (native) #:version "1" #:execution task
  (await-input [answer Any] (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
  (text-result "native result"))
(test-case "native task read subscriptions retain their existing policy without originating-tool permission"
  (define operator (who '("execute")))
  (define subscriber (who '("read")))
  (define store (open-memory-store))
  (define rt (make-runtime (make-interface #:tools (list native)) #:store store
    #:authorize (lambda (principal method _params)
      (not (and (eq? principal subscriber) (equal? method "tools/call"))))))
  (define events (make-async-channel))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "native") #:principal operator) 'taskId))
      (parameterize ([current-custodian (runtime-custodian rt)])
        (thread (lambda () (dispatch rt "subscriptions/listen"
          (hasheq '_meta meta 'notifications (hasheq 'taskIds (list id))) #:principal subscriber #:id "native"
          #:notify (lambda (event) (async-channel-put events event))))))
      (check-equal? (hash-ref (sync/timeout 5 events) 'method) "notifications/subscriptions/acknowledged")
      (let loop ([left 500])
        (define detail (dispatch rt "tasks/get" (hasheq '_meta meta 'taskId id) #:principal subscriber))
        (unless (equal? (hash-ref detail 'status) "input_required")
          (when (zero? left) (error 'test "native task did not await input"))
          (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))))
      (void (dispatch rt "tasks/update" (hasheq '_meta meta 'taskId id 'inputResponses (hasheq 'answer (hasheq 'action "decline")))
                      #:principal operator))
      (let loop ([left 10])
        (define event (sync/timeout 5 events))
        (check-not-false event)
        (unless (equal? (hash-ref (hash-ref event 'params) 'status) "completed")
          (when (zero? left) (error 'test "no native completion notification"))
          (loop (sub1 left))))
      (define final (dispatch rt "tasks/get" (hasheq '_meta meta 'taskId id) #:principal subscriber))
      (check-equal? (hash-ref (hash-ref final 'result) 'content) (list (text-content "native result"))))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
