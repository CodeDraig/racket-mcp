#lang racket/base
(require rackunit racket/async-channel mcp mcp/upstream mcp/upstream-subscription mcp/scenario mcp/stdio)
(for* ([transport '(local stdio http)] [mode '(loss complete cancel empty)])
  (test-case (format "resource feed termination: ~a/~a" transport mode)
    (define version "old")
    (define reads 0)
    (define remote (make-runtime (make-interface #:resources
      (list (make-resource "document" "remote:///{id}"
        (lambda (_) (set! reads (add1 reads)) version)
        #:arguments (list (argument 'id String #f #f)))))))
    (dynamic-wind void
      (lambda ()
        (define (peer method params) (dispatch remote method (hash-set params '_meta (request-meta))))
        (define snapshot (capture-snapshot peer))
        (define source (make-upstream-interface snapshot peer))
        (define cached (make-interface #:resources
          (for/list ([r (interface-descriptor-resources source)]) (struct-copy resource-descriptor r [ttl-ms 60000]))))
        (call-with-scenario-session (view cached #:uris (hash "remote:///{id}" "local:///{id}"))
          (lambda (session)
            (define rt (scenario-session-runtime session))
            (define (read principal)
              (dispatch rt "resources/read" (hasheq 'uri "local:///doc" '_meta (request-meta)) #:principal principal))
            (define alice (read "alice"))
            (define bob (read "bob"))
            (check-equal? reads 2)
            (define (listen uri)
              (define handle (scenario-request session "subscriptions/listen"
                (hasheq 'notifications (hasheq 'resourceSubscriptions (list uri)))))
              (check-equal? (hash-ref (sync/timeout 2 (request-handle-notifications handle)) 'method)
                            "notifications/subscriptions/acknowledged")
              handle)
            (define affected (listen "local:///doc"))
            (define unrelated (listen "local:///other"))
            (define bob-notices (make-async-channel))
            (define bob-ended (make-async-channel))
            (parameterize ([current-custodian (runtime-custodian rt)])
              (thread (lambda ()
                (async-channel-put bob-ended
                  (dispatch-message rt (hasheq 'jsonrpc "2.0" 'id 900 'method "subscriptions/listen"
                    'params (hasheq '_meta (request-meta) 'notifications
                      (hasheq 'resourceSubscriptions '("local:///doc"))))
                    #:principal "bob" #:notify (lambda (notice) (async-channel-put bob-notices notice)))))))
            (check-equal? (hash-ref (sync/timeout 2 bob-notices) 'method) "notifications/subscriptions/acknowledged")
            (define ready (make-semaphore))
            (define result (box #f))
            (define notices (make-async-channel))
            (define (finish value) (set-box! result value) (semaphore-post ready))
            (define handle (request-handle 77 ready result
              (lambda () (unless (sync/timeout 0 (semaphore-peek-evt ready))
                (finish (exn:fail:request-cancelled "local stop" (current-continuation-marks) 77)))) notices))
            (define (request method params)
              (if (equal? method "subscriptions/listen") handle
                  (request-handle 1 (make-semaphore 1) (box (hasheq 'result (hash-ref snapshot (string->symbol method))))
                    void (make-async-channel))))
            (async-channel-put notices (hasheq 'method "notifications/subscriptions/acknowledged"
              'params (hasheq 'notifications (hasheq 'resourceSubscriptions (if (eq? mode 'empty) '() '("remote:///doc")))
                '_meta (hasheq 'io.modelcontextprotocol/subscriptionId 77))))
            (define upstream-result
              (call-with-upstream-resource-subscription rt source snapshot request '("remote:///doc" "remote:///other")
                (lambda (subscription)
                  (set! version "new")
                  (case mode
                    [(loss empty) (finish (exn:fail "upstream transport disappeared" (current-continuation-marks)))]
                    [(complete) (finish (hasheq 'result (hasheq 'resultType "complete"
                      '_meta (hasheq 'io.modelcontextprotocol/subscriptionId 77))))]
                    [(cancel) (stop-upstream-resource-subscription! subscription)])
                  (sync/timeout 2 subscription)) #:principal "alice"))
            (check-not-false upstream-result)
            (define ended (sync/timeout (if (eq? mode 'empty) 0 2) affected))
            (if (eq? mode 'empty) (check-false ended)
             (begin
              (check-true (hash? ended))
              (if (eq? mode 'loss)
                (begin (check-equal? (hash-ref (hash-ref ended 'error) 'code) -32000)
                       (check-regexp-match #rx"re-listen and refresh" (hash-ref (hash-ref ended 'error) 'message)))
                (check-equal? (hash-ref (hash-ref ended 'result) 'resultType) "complete"))))
            (check-false (sync/timeout 0 unrelated))
            (check-false (sync/timeout 0 bob-ended))
            (check-false (sync/timeout 0 bob-notices))
            (check-false (sync/timeout 0 (request-handle-notifications affected)))
            (check-false (sync/timeout 0 (request-handle-notifications unrelated)))
            (check-equal? (read "bob") bob)
            (check-equal? reads 2)
            (check-equal? (hash-ref (car (hash-ref (read "alice") 'contents)) 'text) (if (eq? mode 'empty) "old" "new"))
            (check-equal? reads (if (eq? mode 'empty) 2 3))
            (when (eq? mode 'empty) (request-cancel! affected))
            (request-cancel! unrelated)) #:transport transport #:principal "alice"))
      (lambda () (custodian-shutdown-all (runtime-custodian remote))))))

(test-case "forced cleanup does not repeat a stalled dependency calculation"
  (define remote (make-runtime (make-interface #:resources
    (list (make-resource "document" "remote:///doc" (lambda () "data"))))))
  (dynamic-wind void
    (lambda ()
      (define (peer method params) (dispatch remote method (hash-set params '_meta (request-meta))))
      (define snapshot (capture-snapshot peer))
      (define source (make-upstream-interface snapshot peer))
      (define entered (make-semaphore))
      (define attempts 0)
      (define installed
        (make-interface #:resources
          (list (struct-copy resource-descriptor (car (interface-descriptor-resources source))
                  [depends-on (lambda (_)
                    (set! attempts (add1 attempts)) (semaphore-post entered) (sync never-evt))])
                (make-resource "other" "local:///other" (lambda () "other")))))
      (call-with-scenario-session installed
        (lambda (session)
          (define rt (scenario-session-runtime session))
          (define listeners
            (for/list ([uri '("remote:///doc" "local:///other")])
              (define h (scenario-request session "subscriptions/listen"
                (hasheq 'notifications (hasheq 'resourceSubscriptions (list uri)))))
              (check-equal? (hash-ref (sync/timeout 2 (request-handle-notifications h)) 'method)
                            "notifications/subscriptions/acknowledged") h))
          (define notices (make-async-channel))
          (define ready (make-semaphore))
          (define result (box #f))
          (define failure (exn:fail "lost feed" (current-continuation-marks)))
          (define h (request-handle 77 ready result void notices))
          (define (request method params)
            (if (equal? method "subscriptions/listen") h
                (request-handle 1 (make-semaphore 1) (box (hasheq 'result (hash-ref snapshot (string->symbol method))))
                  void (make-async-channel))))
          (async-channel-put notices (hasheq 'method "notifications/subscriptions/acknowledged"
            'params (hasheq 'notifications (hasheq 'resourceSubscriptions '("remote:///doc"))
              '_meta (hasheq 'io.modelcontextprotocol/subscriptionId 77))))
          (define done (make-async-channel))
          (define retained #f)
          (parameterize ([current-custodian (runtime-custodian rt)])
            (thread (lambda ()
              (async-channel-put done
                (with-handlers ([exn? values])
                  (call-with-upstream-resource-subscription rt source snapshot request '("remote:///doc")
                    (lambda (subscription)
                      (set! retained subscription)
                      (set-box! result failure) (semaphore-post ready)
                      (check-not-false (sync/timeout 2 entered)))
                    #:principal "alice" #:timeout 0.05)
                  'done)))))
          (check-equal? (sync/timeout 2 done) 'done)
          (check-equal? attempts 1)
          (check-eq? (sync/timeout 0 retained) failure)
          ;; When dependency evaluation cannot finish, resource coverage is
          ;; unknown: the fallback closes this principal's resource listeners.
          (for ([listener listeners])
            (define ended (sync/timeout 2 listener))
            (check-equal? (hash-ref (hash-ref ended 'error) 'code) -32000))) #:principal "alice"))
    (lambda () (custodian-shutdown-all (runtime-custodian remote)))))
