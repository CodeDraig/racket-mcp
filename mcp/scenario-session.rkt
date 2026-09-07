#lang racket/base
(require racket/async-channel racket/port "runtime.rkt" "storage.rkt" "clock.rkt"
         "stdio.rkt" "http.rkt" "json.rkt" "interaction.rkt" "subscription.rkt")
(provide call-with-scenario-session scenario-session? scenario-session-runtime
         scenario-session-store scenario-session-clock scenario-session-transport
         scenario-session-principal scenario-call scenario-interact)
(struct scenario-session (runtime store clock transport principal capabilities call [active? #:mutable]))

(define (scenario-call session method [params (hasheq)]
                       #:capabilities [capabilities (scenario-session-capabilities session)])
  (unless (scenario-session-active? session) (error 'scenario-call "scenario session has closed"))
  ((scenario-session-call session) method params capabilities))
(define (scenario-interact session method params #:elicit elicit #:navigate navigate
                           #:max-rounds [rounds 100]
                           #:wait [wait (lambda (ms) (sync (alarm-evt (+ (current-inexact-milliseconds) ms))))])
  (run-interaction (lambda (method params) (scenario-call session method params)) method params
                   #:elicit elicit #:navigate navigate #:max-rounds rounds #:wait wait))

(define (make-local-call rt principal timeout)
  (define ids (box 0))
  (define (next-id)
    (let loop ()
      (define old (unbox ids))
      (if (box-cas! ids old (add1 old)) (add1 old) (loop))))
  (lambda (method params caps)
    (define id (next-id))
    ;; Freeze JSON arguments as the wire clients do, and apply the same envelope,
    ;; metadata, schema and authorization checks through dispatch-message.
    (define message (string->json (json->string
      (hasheq 'jsonrpc "2.0" 'id id 'method method
              'params (hash-set params '_meta (request-meta #:capabilities caps #:extra (hash-ref params '_meta (hasheq))))))))
    (define owner (make-custodian))
    (define result (make-async-channel 1))
    (define cancelled (make-semaphore 0))
    (define worker #f)
    (dynamic-wind void
      (lambda ()
        (set! worker
          (parameterize ([current-custodian owner])
            (thread
              (lambda ()
                (parameterize ([current-output-port (current-error-port)]
                               [current-cancellation-event (semaphore-peek-evt cancelled)]
                               [current-cancelled? (lambda () (and (sync/timeout 0 (semaphore-peek-evt cancelled)) #t))])
                  (async-channel-put result
                    (with-handlers ([(lambda (_) #t) (lambda (failure) (cons #f failure))])
                      (cons #t (dispatch-message rt message #:principal principal)))))))))
        (define outcome
          (sync/timeout timeout result
            (wrap-evt worker
              (lambda (_) (or (sync/timeout 0 result)
                              (cons #f (exn:fail "Scenario request worker terminated" (current-continuation-marks))))))))
        (unless outcome
          (semaphore-post cancelled)
          (sync/timeout 0.2 worker)
          (raise (exn:fail:request-timeout "Scenario request timed out" (current-continuation-marks) id timeout)))
        (if (car outcome) (cdr outcome) (raise (cdr outcome))))
      (lambda () (custodian-shutdown-all owner)))))

(define (call-with-scenario-session interface proc
          #:transport [transport 'local] #:clock [clock (make-manual-clock)]
          #:principal [principal "scenario"] #:adapters [adapters (hasheq)]
          #:capabilities [capabilities (hasheq)] #:state [state #f]
          #:authorize [authorize (lambda (_principal _method _params) #t)]
          #:timeout [timeout 5] #:sse? [sse? #f])
  (unless (memq transport '(local stdio http))
    (raise-argument-error 'call-with-scenario-session "'local, 'stdio, or 'http" transport))
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-scenario-session "procedure accepting one argument" proc))
  (unless (and (rational? timeout) (positive? timeout))
    (raise-argument-error 'call-with-scenario-session "positive finite timeout" timeout))
  (define caps (string->json (json->string capabilities)))
  (unless (hash? caps) (raise-argument-error 'call-with-scenario-session "capabilities object" capabilities))
  (define owner (make-custodian))
  (define store #f)
  (define rt #f)
  (define stop void)
  (define session #f)
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner] [current-mcp-clock clock])
        (set! store (if state (open-sqlite-store state) (open-memory-store)))
        (set! rt (make-runtime interface #:store store #:clock clock #:authorize authorize #:adapters adapters))
        (define call
          (case transport
            [(local) (make-local-call rt principal timeout)]
            [(stdio)
             (define-values (server-in client-out) (make-pipe 1048576))
             (define-values (client-in server-out) (make-pipe 1048576))
             (define server
               (thread (lambda () (serve-stdio rt #:input server-in #:output server-out #:principal principal))))
             (define client (make-stdio-client client-in client-out #:timeout timeout))
             (set! stop (lambda () (client-close! client) (sync/timeout 1 server)
                                    (close-input-port server-in) (close-output-port server-out)))
             (lambda (method params caps) (client-call client method params #:capabilities caps #:timeout timeout))]
            [(http)
             (define confirmation (make-async-channel))
             (set! stop (serve-http rt #:port 0 #:confirmation confirmation #:sse? sse? #:keepalive-seconds (min 1 (/ timeout 2)) #:authenticate (lambda (_) principal)))
             (define port (sync/timeout timeout confirmation))
             (when (exn? port) (raise port))
             (unless (exact-positive-integer? port) (error 'scenario "HTTP server did not start"))
             (define client (make-http-client (format "http://127.0.0.1:~a/mcp" port) #:timeout timeout #:header-timeout timeout))
             (lambda (method params caps) (http-client-call client method params #:capabilities caps #:timeout timeout))]))
        (set! session (scenario-session rt store clock transport principal caps call #t))
        (proc session)))
    (lambda ()
      (when session (set-scenario-session-active?! session #f))
      (dynamic-wind void stop
        (lambda ()
          (when rt (custodian-shutdown-all (runtime-custodian rt)))
          (dynamic-wind void (lambda () (when store (close-store! store)))
            (lambda () (custodian-shutdown-all owner))))))))
