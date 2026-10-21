#lang racket/base
(require "build.rkt" (submod "build.rkt" private) racket/async-channel racket/cmdline racket/file racket/path racket/list racket/pretty racket/string
         "loader.rkt" "scenario.rkt" "private/manifest-diagram.rkt" "private/manifest-docs.rkt" "private/manifest-diff.rkt" "descriptor.rkt" "runtime.rkt" "storage.rkt" "stdio.rkt" "http.rkt" "json.rkt" "upstream.rkt")
(provide run-scenarios main serve-interface serve-interface-command read-manifest read-manifest-examples manifest-diff manifest->mermaid manifest->markdown)
(define (module-path path) `(file ,(path->string (path->complete-path path))))
(define (read-manifest path) (dynamic-require `(submod ,(module-path path) manifest) 'manifest))
(define (read-manifest-examples path)
  (dynamic-require `(submod ,(module-path path) manifest) 'manifest-examples (lambda () '())))
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
                  [(http) (define confirmation (make-async-channel))
                          (define ready (make-channel))
                          ;; Async-channel managers inherit their users'
                          ;; custodians. Receive in a serving-owned worker so
                          ;; the manager cannot outlive this serving lifetime.
                          (thread (lambda () (channel-put ready (sync confirmation))))
                          (define stop (serve-http runtime #:port port #:confirmation confirmation))
                          (dynamic-wind void
                            (lambda ()
                              (define started (sync ready))
                              (when (exn? started) (raise started))
                              (sync never-evt))
                            stop)]
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
(define (read-serving-options program)
  (define transport "stdio") (define state #f) (define port 8000) (define runtime-build-id #f) (define build-id #f)
  (define args
    (command-line #:program program
      #:once-each [("--transport") value "stdio or http" (set! transport value)]
      [("--state") value "SQLite state file" (set! state value)]
      [("--port") value "HTTP port" (set! port (string->number value))]
      [("--build-id") value "Declared application/runtime identity for ordinary loading" (set! build-id (normalize-build-identity value))]
      [("--runtime-build-id") value "Immutable SDK/runtime build identity for captured loading" (set! runtime-build-id value)]
      #:args args args))
  (values transport state port runtime-build-id build-id args))
(define (serve-interface-command interface)
  (define-values (transport state port runtime-build-id build-id args) (read-serving-options "mcp server"))
  (unless (null? args) (error 'serve "unexpected positional arguments: ~s" args))
  (when runtime-build-id
    (error 'serve "captured loading requires raco mcp --runtime-build-id ID [options] serve MODULE; the direct module is already instantiated"))
  (serve-interface interface #:transport transport #:state state #:port port #:build-id build-id))
(define (main)
  (define-values (transport state port runtime-build-id build-id args) (read-serving-options "raco mcp"))
  (unless (>= (length args) 2) (error 'mcp "usage: raco mcp [options] serve|inspect|diagram|docs|check|scenario|snapshot|diff module [other-module]"))
  (define command (car args)) (define path (cadr args))
  (case (string->symbol command)
    [(serve) (serve-interface
               (if runtime-build-id
                   (load-interface (module-path path) #:runtime-build-id runtime-build-id)
                   (dynamic-require (module-path path) 'mcp-interface))
               #:transport transport #:state state #:port port #:build-id build-id)]
    [(inspect) (pretty-write (read-manifest path))]
    [(diagram) (display (manifest->mermaid (read-manifest path)))]
    [(docs) (display (manifest->markdown (read-manifest path) #:title (file-name-from-path path)
                                       #:examples (read-manifest-examples path)))]
    [(check) (define source (path->complete-path path))
             (parameterize ([current-namespace (make-base-namespace)]
                            [current-load-relative-directory (path-only source)])
               (expand (call-with-input-file source
                         (lambda (in)
                           (port-count-lines! in)
                           (parameterize ([read-accept-reader #t]) (read-syntax source in))))))
             (displayln "Expansion checks passed.")]
    [(scenario) (void (run-scenarios path))]
    [(snapshot) (define client (make-http-client path))
                (write-json (capture-snapshot (lambda (method params) (http-client-call client method params)))) (newline)]
    [(diff) (unless (= (length args) 3) (error 'diff "two module paths required"))
            (write-json (manifest-diff (read-manifest path) (read-manifest (caddr args)))) (newline)]
    [else (error 'mcp "unknown command ~a" command)]))
(module+ main (main))
