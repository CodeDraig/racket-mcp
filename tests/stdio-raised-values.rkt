#lang racket/base
(require rackunit mcp/stdio)
(test-case "an arbitrary reader failure settles requests and closes owned ports"
  (define gate (make-semaphore 0))
  (define in (make-input-port 'failing-reader
               (lambda (buffer) (semaphore-wait gate) (raise 'reader-failed)) #f void))
  (define out (open-output-string))
  (define client (make-stdio-client in out #:timeout #f))
  (dynamic-wind void
    (lambda ()
      (define request (client-request client "ping"))
      (semaphore-post gate)
      (define outcome (sync/timeout 2 request))
      (check-true (exn:fail:stdio? outcome))
      (check-eq? (exn:fail:stdio-cause outcome) 'reader-failed)
      (check-not-false (sync/timeout 2 (port-closed-evt in)))
      (check-not-false (sync/timeout 2 (port-closed-evt out))))
    (lambda () (client-close! client))))
(test-case "arbitrary close failures do not skip the other owned port"
  (define-values (in peer) (make-pipe))
  (define input (make-input-port 'failing-close in in (lambda () (raise 'close-failed))))
  (define out (open-output-string))
  (define client (make-stdio-client input out #:timeout #f))
  (dynamic-wind void
    (lambda ()
      (check-not-exn (lambda () (client-close! client)))
      (check-true (port-closed? out)))
    (lambda ()
      (with-handlers ([(lambda (_) #t) void]) (client-close! client))
      (close-input-port in) (close-output-port peer) (close-output-port out))))

(test-case "false raised by a writer remains an error with its original cause"
  (define-values (in peer) (make-pipe))
  (define out (make-output-port 'failing-writer always-evt (lambda args (raise #f)) void))
  (define client (make-stdio-client in out #:timeout #f))
  (dynamic-wind void
    (lambda ()
      (define outcome
        (with-handlers ([exn? values]) (client-call client "ping" #:timeout 2)))
      (check-true (exn:fail:stdio? outcome))
      (check-false (exn:fail:stdio-cause outcome))
      (check-not-false (sync/timeout 2 (port-closed-evt in)))
      (check-not-false (sync/timeout 2 (port-closed-evt out))))
    (lambda () (client-close! client) (close-output-port peer))))
(test-case "existing exceptions preserve identity and borrowed ports stay open"
  (define-values (in peer) (make-pipe))
  (define failure (exn:fail "original" (current-continuation-marks)))
  (define out (make-output-port 'failing-writer always-evt (lambda args (raise failure)) void))
  (define client (make-stdio-client in out #:close-ports? #f #:timeout #f))
  (dynamic-wind void
    (lambda ()
      (check-eq? (sync/timeout 2 (client-request client "ping")) failure)
      (check-false (port-closed? in))
      (check-false (port-closed? out)))
    (lambda () (client-close! client) (close-input-port in)
      (close-output-port peer) (close-output-port out))))
