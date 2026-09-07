#lang racket/base
(require rackunit racket/async-channel mcp mcp/scenario mcp/stdio mcp/subscription)
(define started (make-async-channel))
(tool (waiting)
  (progress! (current-progress-token) 1 #:message "ready")
  (async-channel-put started (current-thread))
  (sync never-evt))
(tool (echo) (text-result "still alive"))
(define iface (make-interface #:tools (list waiting echo)))
(for ([config '((local #f) (stdio #f) (http #f) (http #t))])
  (define escaped #f)
  (define escaped-worker #f)
  (call-with-scenario-session iface
    (lambda (session)
      (define request
        (scenario-request session "tools/call"
          (hasheq 'name "waiting" '_meta (hasheq 'progressToken "first"))))
      (check-true (request-handle? request))
      (define worker (sync/timeout 2 started))
      (check-true (thread? worker))
      (define notice (sync/timeout 2 (request-handle-notifications request)))
      (check-equal? (hash-ref notice 'method) "notifications/progress")
      (check-equal? (hash-ref (hash-ref notice 'params) 'progressToken) "first")
      (check-false (sync/timeout 0 request))
      ;; Concurrent requests continue while the first handler is suspended.
      (define second (scenario-request session "tools/call" (hasheq 'name "echo")))
      (define reply (sync/timeout 2 second))
      (check-equal? (hash-ref (hash-ref reply 'result) 'content) (list (text-content "still alive")))
      (check-not-equal? (request-handle-id request) (request-handle-id second))
      (request-cancel! request)
      (define cancelled (sync/timeout 2 request))
      (check-true (exn:fail:request-cancelled? cancelled))
      (check-eq? (sync/timeout 0 request) cancelled)
      (request-cancel! request)
      (check-eq? (sync/timeout 0 request) cancelled)
      ;; HTTP may need two one-second keep-alive writes plus cleanup grace
      ;; to observe a peer close; the request deadline is five seconds.
      (check-not-false (sync/timeout 3 worker) (format "worker cleanup ~a" config))
      ;; Cancellation after completion must not replace a recorded result.
      (request-cancel! second)
      (check-equal? (sync/timeout 0 second) reply)
      ;; Breaking a synchronous caller cancels its request without ending the session.
      (define caller
        (thread (lambda ()
                  (with-handlers ([exn:break? void])
                    (scenario-call session "tools/call"
                      (hasheq 'name "waiting" '_meta (hasheq 'progressToken "broken")))))))
      (define interrupted-worker (sync/timeout 2 started))
      (check-true (thread? interrupted-worker))
      (break-thread caller)
      (check-not-false (sync/timeout 2 caller))
      (check-not-false (sync/timeout 3 interrupted-worker))
      (set! escaped (scenario-request session "tools/call"
        (hasheq 'name "waiting" '_meta (hasheq 'progressToken "exit"))))
      (set! escaped-worker (sync/timeout 2 started))
      (check-true (thread? escaped-worker)))
    #:transport (car config) #:sse? (cadr config) #:timeout 5)
  ;; Session teardown settles handles before stopping their event machinery.
  (check-true (exn:fail:request-cancelled? (sync/timeout 2 escaped)))
  (check-not-false (sync/timeout 2 escaped-worker)))

;; Local cancellation gives a cooperative handler its cleanup opportunity.
(define cooperative-ready (make-semaphore 0))
(define cooperative-done (make-semaphore 0))
(tool (cooperate)
  (semaphore-post cooperative-ready)
  (sync (current-cancellation-event))
  (semaphore-post cooperative-done)
  (text-result "cancel observed"))
(tool (overflow)
  (for ([i (in-range 300)]) (progress! (current-progress-token) i))
  (text-result "cannot replace overflow"))
(call-with-scenario-session (make-interface #:tools (list cooperate overflow))
  (lambda (session)
    (define h (scenario-request session "tools/call" (hasheq 'name "cooperate")))
    (check-not-false (sync/timeout 2 cooperative-ready))
    (request-cancel! h)
    (check-true (exn:fail:request-cancelled? (sync/timeout 2 h)))
    (check-not-false (sync/timeout 2 cooperative-done))
    (define flooded (scenario-request session "tools/call"
      (hasheq 'name "overflow" '_meta (hasheq 'progressToken "overflow"))))
    (check-true (exn:fail:notification-overflow? (sync/timeout 2 flooded)))
    (check-equal? (for/sum ([i (in-range 300)])
                    (if (sync/timeout 0 (request-handle-notifications flooded)) 1 0)) 256)))
