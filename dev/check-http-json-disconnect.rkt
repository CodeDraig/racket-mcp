#lang racket/base
(require racket/async-channel mcp mcp/http)
;; An open release gate: JSON response mode cannot currently observe a peer
;; disconnect while a handler computes without producing output. Do not count
;; this as an expected-failure native test.
(define entered (make-async-channel))
(tool (blocked)
  (async-channel-put entered (current-thread))
  (sync never-evt))
(module+ main
  (define survived? #f)
  (call-with-scenario-session (make-interface #:tools (list blocked))
    (lambda (session)
      (with-handlers ([exn:fail:http:timeout? void])
        (scenario-call session "tools/call" (hasheq 'name "blocked")))
      (define worker (sync/timeout 5 entered))
      (unless (thread? worker) (error 'probe "handler was not entered"))
      (set! survived? (not (sync/timeout 2 worker))))
    #:transport 'http #:timeout 1/5)
  (when survived? (error 'http-json-disconnect "handler survived the client disconnect until scenario teardown"))
  (displayln "HTTP JSON disconnect reaped the request handler."))
