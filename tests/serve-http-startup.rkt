#lang racket/base
(require rackunit racket/file racket/set racket/tcp mcp mcp/cli mcp/http)

(define interface (make-interface #:server (server-descriptor "startup" "1" #f)))
(define root (current-custodian))
(define directory (make-temporary-file "mcp-http-startup-~a" 'directory))
(dynamic-wind void
  (lambda ()
    (for ([state (list #f (build-path directory "startup.sqlite"))])
      (test-case (if state "HTTP bind failure closes state and workers" "HTTP bind failure without state")
        (define owner (make-custodian))
        (dynamic-wind void
          (lambda ()
            (parameterize ([current-custodian owner])
              (define listener (tcp-listen 0 4 #t "127.0.0.1"))
              (define-values (_ port _remote _remote-port) (tcp-addresses listener #t))
              (define caller-worker (thread (lambda () (sync never-evt))))
              (define before (list->seteq (custodian-managed-list owner root)))
              (define result (make-channel))
              (define worker
                (thread (lambda ()
                          (channel-put result
                            (with-handlers ([(lambda (_) #t) values])
                              (serve-interface interface #:transport "http" #:port port #:state state))))))
              (define failure (sync/timeout 3 result))
              ;; Bound the regression's failure path too: the old CLI waits forever.
              (unless failure (break-thread worker) (sync/timeout 3 result))
              (check-not-false (sync/timeout 3 (thread-dead-evt worker)))
              (check-true (exn:fail:network? failure))
              (check-false (thread-dead? caller-worker))
              ;; Storage transactions use unreachable async-channel managers;
              ;; collect those before comparing this separate caller thread's
              ;; custodian. The existing serve-lifetime checks also run without GC.
              (when state (collect-garbage))
              (check-equal? (list->seteq (custodian-managed-list owner root)) before)))
          (lambda () (custodian-shutdown-all owner)))))
    (test-case "HTTP serves after startup and breaks release its lifetime"
      (define owner (make-custodian))
      (dynamic-wind void
        (lambda ()
          (parameterize ([current-custodian owner])
            (define listener (tcp-listen 0 4 #t "127.0.0.1"))
            (define-values (_ port _remote _remote-port) (tcp-addresses listener #t))
            (tcp-close listener)
            (define caller-worker (thread (lambda () (sync never-evt))))
            (define before (list->seteq (custodian-managed-list owner root)))
            (define result (make-channel))
            (define worker
              (thread (lambda ()
                        (channel-put result
                          (with-handlers ([(lambda (_) #t) values])
                            (serve-interface interface #:transport "http" #:port port
                                             #:state (build-path directory "serving.sqlite")))))))
            (define client (make-http-client (format "http://127.0.0.1:~a/mcp" port) #:timeout 0.5 #:header-timeout 0.5))
            (define deadline (+ (current-inexact-milliseconds) 3000))
            (define probe-owner (make-custodian))
            (define reply
              (dynamic-wind void
                (lambda ()
                  (parameterize ([current-custodian probe-owner])
                    (let loop ()
                      (define response (with-handlers ([exn:fail:network? values]) (http-client-call client "server/discover")))
                      (cond [(not (exn? response)) response]
                            [(>= (current-inexact-milliseconds) deadline) (raise response)]
                            [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop)]))))
                (lambda () (custodian-shutdown-all probe-owner))))
            (check-equal? (hash-ref (hash-ref reply 'result) 'resultType) "complete")
            (check-false (thread-dead? worker))
            (break-thread worker)
            (check-true (exn:break? (sync/timeout 3 result)))
            (check-not-false (sync/timeout 3 (thread-dead-evt worker)))
            (check-false (thread-dead? caller-worker))
            (collect-garbage)
            (check-equal? (list->seteq (custodian-managed-list owner root)) before)))
        (lambda () (custodian-shutdown-all owner)))))
  (lambda () (delete-directory/files directory)))
