#lang racket/base
(require racket/path
         racket/pretty
         "loader.rkt"
         "scenario.rkt"
         "http.rkt"
         "json.rkt"
         "upstream.rkt"
         "private/interface-serving.rkt"
         "private/serving-options.rkt"
         "private/manifest-diagram.rkt"
         "private/manifest-docs.rkt"
         "private/manifest-diff.rkt")
(provide run-scenarios main serve-interface serve-interface-command read-manifest read-manifest-examples manifest-diff manifest->mermaid manifest->markdown)

(define (module-path path) `(file ,(path->string (path->complete-path path))))
(define (read-manifest path) (dynamic-require `(submod ,(module-path path) manifest) 'manifest))
(define (read-manifest-examples path)
  (dynamic-require `(submod ,(module-path path) manifest) 'manifest-examples))
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
