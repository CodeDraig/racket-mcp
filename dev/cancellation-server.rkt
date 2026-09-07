#lang racket/base
(require mcp mcp/stdio mcp/subscription)
;; Keep the actual worker object so the independent client can distinguish a
;; locally cancelled call from server-side worker cleanup.
(define last-worker #f)
(define waiting
  (make-tool "wait" '()
    (lambda (_)
      (set! last-worker (current-thread))
      (for ([value '(0 1/2 1)])
        (progress! (current-progress-token) value #:total 1))
      (sync never-evt))
    #:description "Report progress, then wait until request cancellation."))
(define status
  (make-tool "worker-status" '()
    (lambda (_)
      (text-result (cond [(not last-worker) "not-started"]
                         [(thread-dead? last-worker) "stopped"]
                         [else "running"])))
    #:description "Inspect whether the cancelled request worker stopped."))
(serve-stdio (make-runtime (make-interface
  #:server (server-descriptor "cancellation-interop" "1" "")
  #:tools (list waiting status))))
