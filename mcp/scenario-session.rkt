#lang racket/base
(require "private/scenario-local-request.rkt")
(require racket/async-channel
         "runtime.rkt"
         "storage.rkt"
         "clock.rkt"
         "stdio.rkt"
         "http.rkt"
         "json.rkt"
         "interaction.rkt")
(provide call-with-scenario-session scenario-session? scenario-session-runtime
         scenario-session-store scenario-session-clock scenario-session-transport
         scenario-session-principal scenario-session-connected? scenario-disconnect! scenario-reconnect! scenario-request scenario-call scenario-interact)
(struct scenario-session (runtime store clock transport principal capabilities timeout [request #:mutable] owner pending lock [active? #:mutable] [connected? #:mutable] connect disconnect))

(define (scenario-disconnect! session)
  (call-with-semaphore (scenario-session-lock session)
    (lambda ()
      (unless (scenario-session-active? session) (error 'scenario-disconnect! "scenario session has closed"))
      (when (eq? (scenario-session-transport session) 'local)
        (error 'scenario-disconnect! "local scenarios have no transport connection"))
      (when (scenario-session-connected? session)
        (set-scenario-session-connected?! session #f)
        ((scenario-session-disconnect session))))))
(define (scenario-reconnect! session)
  (call-with-semaphore (scenario-session-lock session)
    (lambda ()
      (unless (scenario-session-active? session) (error 'scenario-reconnect! "scenario session has closed"))
      (unless (scenario-session-connected? session)
        (parameterize ([current-custodian (scenario-session-owner session)]
                       [current-mcp-clock (scenario-session-clock session)])
          (define request ((scenario-session-connect session)))
          (set-scenario-session-request! session request)
          (set-scenario-session-connected?! session #t))))))

(define (scenario-request session method [params (hasheq)]
                          #:capabilities [capabilities (scenario-session-capabilities session)]
                          #:timeout [timeout (and (not (equal? method "subscriptions/listen"))
                                                  (scenario-session-timeout session))])
  (unless (or (not timeout) (and (rational? timeout) (positive? timeout)))
    (raise-argument-error 'scenario-request "#f or positive finite timeout" timeout))
  (call-with-semaphore (scenario-session-lock session)
    (lambda ()
      (unless (scenario-session-active? session) (error 'scenario-request "scenario session has closed"))
      (unless (scenario-session-connected? session) (error 'scenario-request "scenario transport is disconnected"))
      (parameterize ([current-custodian (scenario-session-owner session)])
        (define handle ((scenario-session-request session) method params capabilities timeout))
        (hash-set! (scenario-session-pending session) handle #t)
        (thread (lambda ()
                  (sync handle)
                  (call-with-semaphore (scenario-session-lock session)
                    (lambda () (hash-remove! (scenario-session-pending session) handle)))))
        handle))))
(define (scenario-call session method [params (hasheq)]
                       #:capabilities [capabilities (scenario-session-capabilities session)]
                       #:timeout [timeout (and (not (equal? method "subscriptions/listen"))
                                               (scenario-session-timeout session))])
  (define handle (scenario-request session method params #:capabilities capabilities #:timeout timeout))
  (dynamic-wind void
    (lambda ()
      (define result (sync handle))
      (if (exn? result) (raise result) result))
    (lambda () (unless (sync/timeout 0 handle) (request-cancel! handle)))))
(define (scenario-interact session method params #:elicit elicit #:navigate navigate
                           #:max-rounds [rounds 100]
                           #:wait [wait (lambda (ms) (sync (alarm-evt (+ (current-inexact-milliseconds) ms))))])
  (run-interaction (lambda (method params) (scenario-call session method params)) method params
                   #:elicit elicit #:navigate navigate #:max-rounds rounds #:wait wait))

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
  (define drop void)
  (define session #f)
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner] [current-mcp-clock clock])
        (set! store (if state (open-sqlite-store state) (open-memory-store)))
        (set! rt (make-runtime interface #:store store #:clock clock #:authorize authorize #:adapters adapters))
        (define (connect)
          (stop)
          (case transport
            [(local) (make-local-request rt principal)]
            [(stdio)
             (define-values (server-in client-out) (make-pipe 1048576))
             (define-values (client-in server-out) (make-pipe 1048576))
             (define injected-loss? #f)
             (define server-owner (make-custodian))
             (define server
               (parameterize ([current-custodian server-owner])
                 (thread (lambda ()
                           (with-handlers ([exn:fail? (lambda (failure) (unless injected-loss? (raise failure)))])
                             (serve-stdio rt #:input server-in #:output server-out #:principal principal))))))
             (define client (make-stdio-client client-in client-out #:timeout timeout))
             (set! drop
               (lambda ()
                 ;; Actual EOF in both directions; the client observes transport
                 ;; failure rather than a locally synthesized cancellation.
                 (set! injected-loss? #t)
                 (close-output-port server-out)
                 (close-output-port client-out)
                 (sync/timeout 0.2 server)
                 (custodian-shutdown-all server-owner)))
             (set! stop (lambda () (client-close! client) (drop)
                                    (close-input-port server-in)))
             (lambda (method params caps timeout) (client-request client method params #:capabilities caps #:timeout timeout))]
            [(http)
             (define confirmation (make-async-channel))
             (set! stop (serve-http rt #:port 0 #:confirmation confirmation #:sse? sse? #:keepalive-seconds (min 1 (/ timeout 2)) #:authenticate (lambda (_) principal)))
             (define port (sync/timeout timeout confirmation))
             (when (exn? port) (raise port))
             (unless (exact-positive-integer? port) (error 'scenario "HTTP server did not start"))
             (set! drop stop)
             (define client (make-http-client (format "http://127.0.0.1:~a/mcp" port) #:timeout timeout #:header-timeout timeout))
             (lambda (method params caps timeout) (http-client-request client method params #:capabilities caps #:timeout timeout))]))
        (set! session (scenario-session rt store clock transport principal caps timeout #f owner (make-hasheq) (make-semaphore 1) #t #f connect (lambda () (drop))))
        (scenario-reconnect! session)
        (proc session)))
    (lambda ()
      (when session
        (define pending
          (call-with-semaphore (scenario-session-lock session)
            (lambda ()
              (set-scenario-session-active?! session #f)
              (set-scenario-session-connected?! session #f)
              (hash-keys (scenario-session-pending session)))))
        (for ([handle (in-list pending)]) (request-cancel! handle)))
      (dynamic-wind void stop
        (lambda ()
          (when rt (custodian-shutdown-all (runtime-custodian rt)))
          (dynamic-wind void (lambda () (when store (close-store! store)))
            (lambda () (custodian-shutdown-all owner))))))))
