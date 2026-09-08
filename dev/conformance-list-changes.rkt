#lang racket/base
(require racket/async-channel mcp mcp/http mcp/clock mcp/subscription
         mcp/private/http-request
         web-server/web-server web-server/servlet-dispatch web-server/safety-limits
         (only-in web-server/private/connection-manager connection-custodian))
(provide serve-changing-conformance)

;; Diagnostic application routing, not an SDK hot-reload API. Every request uses
;; one immutable interface snapshot. An accepted subscription retains its runtime
;; and shares the same event hub with later snapshots.
(define (serve-changing-conformance base #:port [port 0] #:confirmation [confirmation #f]
                                   #:store [store #f])
  (define owner (make-custodian))
  (with-handlers ([(lambda (_) #t) (lambda (e) (custodian-shutdown-all owner) (raise e))])
    (parameterize ([current-custodian owner])
      (define clock (current-mcp-clock))
      (define hub (make-subscription-hub))
      (define lock (make-semaphore 1))
      (define selected 0)
      (define (change! bit method)
        (call-with-semaphore lock
          (lambda ()
            ;; Toggle rather than notify without a mutation on repeated calls.
            (set! selected (bitwise-xor selected bit))
            (publish-change! hub method (hasheq))))
        (text-result "List changed."))
      (define hooks
        (make-interface #:tools
          (list (make-tool "test_trigger_tool_change" '()
                          (lambda (_) (change! 1 "notifications/tools/list_changed"))
                          #:description "Toggle a diagnostic tool in the published list.")
                (make-tool "test_trigger_prompt_change" '()
                          (lambda (_) (change! 2 "notifications/prompts/list_changed"))
                          #:description "Toggle a diagnostic prompt in the published list."))))
      (define additions
        (make-interface
          #:tools (list (make-tool "diagnostic_added_tool" '() (lambda (_) (text-result "Added."))
                                   #:description "A dynamically published diagnostic tool."))
          #:prompts (list (make-prompt "diagnostic_added_prompt" '()
                            (lambda (_) (list (role "user" (text-content "Added."))))
                            #:description "A dynamically published diagnostic prompt."))))
      (define handlers
        (for/vector ([index (in-range 4)])
          (define extra
            (view additions #:exclude
              (append (if (bitwise-bit-set? index 0) '() '("diagnostic_added_tool"))
                      (if (bitwise-bit-set? index 1) '() '("diagnostic_added_prompt")))))
          (define combined (mount-interfaces base hooks extra))
          (define iface (struct-copy interface-descriptor combined [server (interface-descriptor-server base)]))
          (define rt (make-runtime iface #:store store #:recover-tasks? #f #:clock clock))
          ;; struct-copy of the public parent drops the private clock subtype;
          ;; explicitly restore this fixture's captured clock around each request.
          (define handler (make-http-handler (struct-copy runtime rt [subscriptions hub])
                                             #:origins (if (positive? port)
                                               (list (format "http://127.0.0.1:~a" port)
                                                     (format "http://localhost:~a" port)) '())
                                             #:keepalive-seconds 0.1))
          (lambda (request) (parameterize ([current-mcp-clock clock]) (handler request)))))
      (define dispatcher
        (dispatch/servlet
          (lambda (request)
            (define handler (call-with-semaphore lock (lambda () (vector-ref handlers selected))))
            (handler request))))
      (define stop
        (serve #:port port #:listen-ip "127.0.0.1" #:confirmation-channel confirmation
               #:safety-limits (make-safety-limits #:max-request-body-length 1048576)
               #:dispatch
               (lambda (connection request)
                 (parameterize ([current-http-request-custodian (connection-custodian connection)])
                   (call-with-http-request-scope (lambda () (dispatcher connection request)))))))
      (lambda ()
        (close-subscriptions! hub)
        (stop)
        (custodian-shutdown-all owner)))))

(module+ main
  (require (prefix-in core: "conformance-server.rkt") mcp/storage)
  (define arguments (current-command-line-arguments))
  (define store (open-sqlite-store (vector-ref arguments 1)))
  (define stop (serve-changing-conformance core:mcp-interface
                                          #:port (string->number (vector-ref arguments 0)) #:store store))
  (dynamic-wind void (lambda () (sync never-evt))
                (lambda () (stop) (close-store! store))))
