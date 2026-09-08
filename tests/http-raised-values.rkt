#lang racket/base
(require rackunit mcp/http mcp/stdio)
(define (denying-guard failure reached [owned #f])
  (make-security-guard (current-security-guard) void
    (lambda arguments
      (when owned
        (define started (make-semaphore 0))
        (set-box! owned (thread (lambda () (semaphore-post started) (sync never-evt))))
        (semaphore-wait started))
      (semaphore-post reached)
      (raise failure))))
(for ([failure (in-list (list 'network-denied #f
                             (exn "base exception" (current-continuation-marks))
                             (exn:fail "ordinary failure" (current-continuation-marks))))])
  (test-case (format "HTTP network policy failure settles the handle: ~s" failure)
    (define owner (make-custodian))
    (dynamic-wind void
      (lambda ()
        (parameterize ([current-custodian owner])
          (define reached (make-semaphore 0))
          (define client (make-http-client "http://127.0.0.1:1/mcp" #:timeout #f #:header-timeout #f))
          (for ([attempt (in-range 2)])
            (define owned (box #f))
            (define handle
              (parameterize ([current-security-guard (denying-guard failure reached owned)])
                (http-client-request client "server/discover"
                  (hasheq '_meta (hasheq 'progressToken "reusable")))))
            (check-not-false (sync/timeout 2 reached))
            (define outcome (sync/timeout 2 handle))
            (check-true (exn? outcome))
            (if (exn? failure)
                (check-eq? outcome failure)
                (begin
                  (check-true (exn:fail:http:transport? outcome))
                  (check-eq? (exn:fail:http:transport-cause outcome) failure)))
            (check-not-false (sync/timeout 2 (thread-dead-evt (unbox owned))))
            (request-cancel! handle)
            (check-eq? (sync handle) outcome))))
      (lambda () (custodian-shutdown-all owner)))))

(test-case "synchronous HTTP calls raise a wrapped false failure"
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner])
        (define outcome (make-channel))
        (define reached (make-semaphore 0))
        (define worker
          (thread
            (lambda ()
              (channel-put outcome
                (with-handlers ([(lambda (_) #t) (lambda (value) (cons 'raised value))])
                  (parameterize ([current-security-guard (denying-guard #f reached)])
                    (cons 'returned
                      (http-client-call (make-http-client "http://127.0.0.1:1/mcp"
                                                         #:timeout #f #:header-timeout #f)
                                        "server/discover"))))))))
        (check-not-false (sync/timeout 2 reached))
        (define result (sync/timeout 2 outcome))
        (check-true (pair? result))
        (check-eq? (car result) 'raised)
        (check-true (exn:fail:http:transport? (cdr result)))
        (check-false (exn:fail:http:transport-cause (cdr result)))
        (check-not-false (sync/timeout 2 worker))))
    (lambda () (custodian-shutdown-all owner))))
