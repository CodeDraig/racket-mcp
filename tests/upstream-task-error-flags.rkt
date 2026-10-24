#lang racket/base
(require rackunit racket/file racket/async-channel mcp mcp/tasks mcp/upstream)
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define output (object-schema (hasheq 'n Integer)))
(define malformed (list "false" 0 json-null '() (hasheq)))

(for* ([sqlite? '(#f #t)] [mode '(poll observe)] [schema? '(#f #t)]
       [flag (append malformed (list missing #f #t))])
  (test-case (format "upstream isError contract: sqlite ~s, ~a, schema ~s, flag ~s" sqlite? mode schema? flag)
    (define directory (and sqlite? (make-temporary-file "upstream-error-flags-~a" 'directory)))
    (define path (and directory (build-path directory "state.sqlite")))
    (define store (if path (open-sqlite-store path) (open-memory-store)))
    (define valid-flag? (or (missing? flag) (boolean? flag)))
    (define wire-tool (hasheq 'name "work" 'inputSchema (hasheq 'type "object")))
    (define snapshot
      (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities
                (hasheq 'tools (hasheq) 'resources (hasheq) 'extensions (hash-ref caps 'extensions)))
        'tools/list (hasheq 'tools (list (if schema? (hash-set wire-tool 'outputSchema output) wire-tool)))
        'resources/list (hasheq 'resources (list (hasheq 'name "doc" 'uri "remote:///doc")))
        'resources/templates/list (hasheq 'resourceTemplates '()) 'prompts/list (hasheq 'prompts '())))
    (define base (hasheq 'taskId "remote-task" 'status "working" 'createdAt "2026-10-24T00:00:00Z"
                        'lastUpdatedAt "2026-10-24T00:00:00Z" 'ttlMs 60000))
    (define value
      (structured-result (hasheq 'n (if (and valid-flag? (not (eq? flag #t))) 7 "bad"))
        #:content (list (hasheq 'type "resource_link" 'name "doc" 'uri "remote:///doc"))))
    (define completion (hash-set* base 'resultType "complete" 'status "completed" 'result
                        (if (missing? flag) value (hash-set value 'isError flag))))
    (define polls 0)
    (define (peer method params)
      (cond [(hash-ref snapshot (string->symbol method) #f) => values]
            [(equal? method "tools/call") (hash-set base 'resultType "task")]
            [(equal? method "tasks/get") (set! polls (add1 polls)) completion]
            [else (error 'peer "unexpected method ~a" method)]))
    (define iface (view (make-upstream-interface snapshot peer #:bridge
                   (make-upstream-bridge #:identity "flags" #:version "1" #:credential-id (lambda (_) "credential")))
                  #:uris (hash "remote:///doc" "local:///doc")))
    (define clock (make-manual-clock #:seconds 100))
    (define rt (make-runtime iface #:store store #:clock clock))
    (define events (make-async-channel))
    (define (poll id) (dispatch rt "tasks/get" (hasheq '_meta meta 'taskId id) #:principal "alice"))
    (dynamic-wind void
      (lambda ()
        (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "work") #:principal "alice") 'taskId))
        (parameterize ([current-custodian (runtime-custodian rt)])
          (thread (lambda () (dispatch rt "subscriptions/listen"
            (hasheq '_meta meta 'notifications (hasheq 'taskIds (list id))) #:principal "alice" #:id 99
            #:notify (lambda (event) (async-channel-put events event))))))
        (define acknowledgement (sync/timeout 3 events))
        (check-not-false acknowledgement)
        (check-equal? (hash-ref acknowledgement 'method) "notifications/subscriptions/acknowledged")
        (define before (load-instance store id))
        (define journal (instance-events store id))
        (define (receive)
          (if (eq? mode 'poll) (poll id)
              (runtime-observe-upstream-task! rt id completion #:principal "alice" #:capabilities caps)))
        (unless valid-flag?
          (check-exn exn:fail:mcp? receive)
          (check-equal? (load-instance store id) before)
          (check-equal? (instance-events store id) journal)
          (check-false (sync/timeout 0 events))
          ;; Rejection must leave the task able to accept a later valid outcome.
          (set! completion (hash-set completion 'result (hash-remove (hash-set value 'structuredContent (hasheq 'n 7)) 'isError))))
        (define final (receive))
        (check-equal? (hash-ref final 'status) "completed")
        (check-equal? (hash-ref (car (hash-ref (hash-ref final 'result) 'content)) 'uri) "local:///doc")
        (define notice (sync/timeout 3 events))
        (check-not-false notice)
        (check-equal? (hash-ref (hash-ref notice 'params) 'result) (hash-ref final 'result))
        (check-equal? polls (if (eq? mode 'observe) 0 (if valid-flag? 1 2)))
        (define terminal (load-instance store id))
        (when path
          (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
          (set! store (open-sqlite-store path)) (set! rt (make-runtime iface #:store store #:clock clock)))
        (define previous-polls polls)
        (check-equal? (poll id) final)
        (check-equal? polls previous-polls)
        (check-equal? (load-instance store id) terminal)
        (unless valid-flag?
          ;; Older completed records can contain flags accepted by the old code.
          (define state (stored-instance-state terminal))
          (define task (hash-ref state 'task))
          (define legacy (update-instance! store terminal (hash-set state 'task
            (hash-set task 'result (hash-set (hash-ref task 'result) 'isError flag)))))
          (define legacy-journal (instance-events store id))
          (check-exn exn:fail:mcp? (lambda () (poll id)))
          (check-equal? (load-instance store id) legacy)
          (check-equal? (instance-events store id) legacy-journal)
          (check-equal? polls previous-polls)
          (check-false (sync/timeout 0 events))))
      (lambda ()
        (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
        (when directory (delete-directory/files directory))))))
