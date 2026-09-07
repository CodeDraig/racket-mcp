#lang racket/base
(require racket/async-channel mcp mcp/scenario mcp/upstream mcp/http
         (prefix-in fixture: "conformance-tasks.rkt"))
;; The independent harness reaches the HTTP bridge; its peer uses native stdio.
;; Both stores are explicitly ephemeral development fixtures.
(module+ main
  (define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
  (call-with-scenario-session fixture:mcp-interface
    (lambda (peer)
      (define snapshot (capture-snapshot (lambda (m p) (scenario-call peer m p))))
      (define (request m p)
        (define context (current-request-context))
        (scenario-call peer m p #:capabilities (if context (request-context-capabilities context) caps)))
      (define interface (make-upstream-interface snapshot request #:bridge
        (make-upstream-bridge #:identity "conformance-peer" #:version "1" #:credential-id (lambda (_) "peer-account"))))
      (define store (open-memory-store))
      (define rt (make-runtime interface #:store store))
      (dynamic-wind void
        (lambda ()
          (define confirmation (make-async-channel))
          (define stop (serve-http rt #:port 0 #:confirmation confirmation))
          (dynamic-wind void
            (lambda ()
              (define port (sync confirmation))
              (when (exn? port) (raise port))
              (printf "http://127.0.0.1:~a/mcp\n" port) (flush-output)
              (sync never-evt)) stop))
        (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
    #:transport 'stdio #:principal "peer-owner" #:capabilities caps #:timeout 90))
