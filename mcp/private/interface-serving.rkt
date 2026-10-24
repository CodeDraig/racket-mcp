#lang racket/base
(require racket/list "../build.rkt" (submod "../build.rkt" private) "../descriptor.rkt" "../runtime.rkt"
         "../storage.rkt" "../stdio.rkt" "../http.rkt" "serving-options.rkt")
(provide serve-interface serve-interface-command)
(define (serve-interface interface #:transport [transport "stdio"] #:state [state #f] #:port [port 8000] #:build-id [build-id (current-build-identity)])
  (set! build-id (normalize-build-identity build-id))
  (unless (interface-descriptor-server interface) (error 'serve "an executable interface requires a server declaration"))
  (when (and (interface-requires-state? interface) (not state))
    (error 'serve "durable workflows and upstream bridges require an explicit --state file"))
  (define serving-breaks? (break-enabled))
  (parameterize-break #f
    ;; Acquisition is part of the serving lifetime too. Keep store transaction
    ;; supervision alive until runtime and transport workers have stopped.
    (define owner (make-custodian))
    (define workers #f)
    (define store #f)
    (define completed? #f)
    (dynamic-wind void
      (lambda ()
        (parameterize-break serving-breaks?
          (parameterize ([current-custodian owner])
            (set! store (and state (open-sqlite-store state)))
            (set! workers (make-custodian))
            (parameterize ([current-custodian workers])
              (define runtime (make-runtime interface #:store store #:build-id build-id))
              (begin0
                (case (string->symbol transport)
                  [(stdio) (serve-stdio runtime)]
                  [(http) (define stop (serve-http runtime #:port port))
                          (dynamic-wind void (lambda () (sync never-evt)) stop)]
                  [else (error 'serve "unknown transport ~a" transport)])
                (set! completed? #t))))))
      (lambda ()
        (define failures '())
        (define (attempt thunk)
          (with-handlers ([(lambda (_) #t) (lambda (failure) (set! failures (cons failure failures)))])
            (thunk)))
        (when workers (attempt (lambda () (custodian-shutdown-all workers))))
        (when store (attempt (lambda () (close-store! store))))
        (attempt (lambda () (custodian-shutdown-all owner)))
        ;; On unwinding, preserve the original raised value or control transfer.
        ;; On ordinary return, expose a cleanup failure after attempting every step.
        (when (and completed? (pair? failures)) (raise (last failures)))))))
(define (serve-interface-command interface)
  (define-values (transport state port runtime-build-id build-id args) (read-serving-options "mcp server"))
  (unless (null? args) (error 'serve "unexpected positional arguments: ~s" args))
  (when runtime-build-id
    (error 'serve "captured loading requires raco mcp --runtime-build-id ID [options] serve MODULE; the direct module is already instantiated"))
  (serve-interface interface #:transport transport #:state state #:port port #:build-id build-id))
