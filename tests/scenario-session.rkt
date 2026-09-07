#lang racket/base
(require rackunit racket/file racket/list racket/async-channel mcp mcp/scenario mcp/stdio mcp/http)
(define gates (make-async-channel))
(tool (identify)
  (structured-result (hasheq 'principal (request-context-principal (current-request-context)) 'time (mcp-current-seconds))))
(tool (blocked)
  (async-channel-put gates (current-thread))
  (sync never-evt))
(workflow (approve [name String]) #:version "1"
  (checkpoint [started Integer] (mcp-current-seconds))
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Proceed?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (perform [saved String] #:adapter save #:policy idempotent name)
  (structured-result (hasheq 'name saved 'started started 'action (hash-ref answer 'action))))
(workflow (tasked) #:version "1" #:execution task
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Task input" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (structured-result (hasheq 'time (mcp-current-seconds) 'action (hash-ref answer 'action))))
(define iface (make-interface #:tools (list identify blocked approve tasked)))
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(for ([configuration '((local #f) (stdio #f) (http #f) (http #t))])
  (define transport (car configuration))
  (define clock (make-manual-clock #:seconds 100))
  (define effects '())
  (define escaped #f)
  (define adapters
    (hasheq 'save (effect-adapter 'idempotent
                    (lambda (input key transaction)
                      (set! effects (cons (list input key transaction) effects))
                      (string-append "saved:" input)))))
  (define (run proc)
    (call-with-scenario-session iface proc #:transport transport #:clock clock
      #:principal "alice" #:adapters adapters #:capabilities caps #:sse? (cadr configuration)
      #:authorize (lambda (principal _method _params) (equal? principal "alice"))))
  (check-equal?
    (run
      (lambda (session)
        (set! escaped session)
        (check-eq? (scenario-session-clock session) clock)
        (check-eq? (scenario-session-transport session) transport)
        (check-equal? (scenario-session-principal session) "alice")
        (define first (scenario-call session "tools/call" (hasheq 'name "identify")))
        (check-equal? (hash-ref (hash-ref first 'result) 'structuredContent) (hasheq 'principal "alice" 'time 100))
        (void (manual-clock-advance! clock 1))
        (define second (scenario-call session "tools/call" (hasheq 'name "identify")))
        (check-not-equal? (hash-ref first 'id) (hash-ref second 'id))
        (check-equal? (hash-ref (hash-ref second 'result) 'structuredContent) (hasheq 'principal "alice" 'time 101))
        (check-equal? (hash-ref (hash-ref (scenario-call session "tools/call" (hasheq 'name "missing")) 'error) 'code) -32602)
        (define final
          (scenario-interact session "tools/call" (hasheq 'name "approve" 'arguments (hasheq 'name "Ada"))
            #:elicit (lambda (input)
                       (check-equal? (hash-ref input 'message) "Proceed?")
                       (hasheq 'action "decline"))
            #:navigate (lambda (_) (error 'test "unexpected navigation"))))
        (check-equal? (hash-ref (hash-ref final 'result) 'structuredContent)
                      (hasheq 'name "saved:Ada" 'started 101 'action "decline"))
        (define task-result
          (scenario-interact session "tools/call" (hasheq 'name "tasked")
            #:elicit (lambda (input)
                       (check-equal? (hash-ref input 'message) "Task input")
                       (hasheq 'action "cancel"))
            #:navigate (lambda (_) (error 'test "unexpected navigation"))))
        (check-equal? (hash-ref (hash-ref task-result 'result) 'status) "completed")
        (check-equal? (hash-ref (hash-ref (hash-ref task-result 'result) 'result) 'structuredContent)
                      (hasheq 'time 101 'action "cancel"))
        'finished))
    'finished)
  (check-equal? (length effects) 1)
  (check-exn #rx"session has closed" (lambda () (scenario-call escaped "server/discover")))
  ;; Explicit SQLite reuse resumes through the same principal and adapter path.
  (define path (make-temporary-file "scenario-state-~a.sqlite"))
  (dynamic-wind void
    (lambda ()
      (define pending
        (call-with-scenario-session iface
          (lambda (session) (scenario-call session "tools/call" (hasheq 'name "approve" 'arguments (hasheq 'name "Grace"))))
          #:transport transport #:clock clock #:state path #:principal "alice" #:adapters adapters #:capabilities caps))
      (void (manual-clock-advance! clock 10))
      (define complete
        (call-with-scenario-session iface
          (lambda (session)
            (scenario-call session "tools/call"
              (hasheq 'name "approve" 'arguments (hasheq 'name "Grace")
                      'requestState (hash-ref (hash-ref pending 'result) 'requestState)
                      'inputResponses (hasheq 'answer (hasheq 'action "cancel")))))
          #:transport transport #:clock clock #:state path #:principal "alice" #:adapters adapters #:capabilities caps))
      (check-equal? (hash-ref (hash-ref complete 'result) 'structuredContent)
                    (hasheq 'name "saved:Grace" 'started 101 'action "cancel")))
    (lambda () (delete-file path)))
  ;; Calls are bounded even when a handler ignores cooperative cancellation.
  (define timed-worker #f)
  (call-with-scenario-session iface
    (lambda (session)
      (check-exn (lambda (failure) (or (exn:fail:request-timeout? failure) (exn:fail:http:timeout? failure)))
        (lambda () (scenario-call session "tools/call" (hasheq 'name "blocked"))))
      (define worker (sync/timeout 2 gates))
      (check-true (thread? worker))
      (set! timed-worker worker)
      (unless (and (eq? transport 'http) (not (cadr configuration)))
        (check-not-false (sync/timeout 2 worker))))
    #:transport transport #:timeout 1/5 #:sse? (cadr configuration))
  (check-not-false (sync/timeout 2 timed-worker)))

;; The form's configuration runs only with its test submodule, once and in order.
(define dir (make-temporary-file "scenario-form-~a" 'directory))
(dynamic-wind void
  (lambda ()
    (define path (build-path dir "example.rkt"))
    (display-to-file
#<<MODULE
#lang mcp
(module+ test (require rackunit) (define order '())
  (define (record tag value) (set! order (append order (list tag))) value))
(tool (identity) (text-result (request-context-principal (current-request-context))))
(scenario (configured context)
  #:interface (record 'interface mcp-interface)
  #:transport (record 'transport 'stdio)
  #:clock (record 'clock (make-manual-clock))
  #:principal (record 'principal "configured")
  (check-equal? order '(interface transport clock principal))
  (check-equal? (hash-ref (hash-ref (scenario-call context "tools/call" (hasheq 'name "identity")) 'result) 'content)
                (list (text-content "configured"))))
MODULE
      path)
    (check-equal? (run-scenarios path) '(0 . 1))
    (for ([body (list
                 "(scenario (bad context) (void))"
                 "(scenario (bad 42) #:interface (make-interface) (void))"
                 "(scenario (bad context) #:interface (make-interface) #:clock (make-manual-clock) #:clock (make-manual-clock) (void))")]
          [i (in-naturals)])
      (define invalid (build-path dir (format "invalid~a.rkt" i)))
      (display-to-file (string-append "#lang mcp\n" body "\n") invalid)
      (check-exn exn:fail:syntax? (lambda () (run-scenarios invalid)))))
  (lambda () (delete-directory/files dir)))
