#lang racket/base
(require racket/cmdline racket/file racket/path racket/list racket/pretty racket/string
         "private/manifest-diagram.rkt" "descriptor.rkt" "runtime.rkt" "storage.rkt" "stdio.rkt" "http.rkt" "json.rkt" "upstream.rkt")
(provide main serve-interface read-manifest manifest-diff manifest->mermaid)
(define (module-path path) `(file ,(path->string (path->complete-path path))))
(define (read-manifest path) (dynamic-require `(submod ,(module-path path) manifest) 'manifest))
(define (serve-interface interface #:transport [transport "stdio"] #:state [state #f] #:port [port 8000])
  (unless (interface-descriptor-server interface) (error 'serve "an executable interface requires a server declaration"))
  (when (and (or (ormap tool-descriptor-workflow (interface-descriptor-tools interface))
                 (ormap prompt-descriptor-workflow (interface-descriptor-prompts interface))
                 (ormap resource-descriptor-workflow (interface-descriptor-resources interface))) (not state))
    (error 'serve "durable workflows require an explicit --state file"))
  (define store (and state (open-sqlite-store state)))
  (define runtime (make-runtime interface #:store store))
  (dynamic-wind void
    (lambda ()
      (case (string->symbol transport)
        [(stdio) (serve-stdio runtime)]
        [(http) (define stop (serve-http runtime #:port port))
                (dynamic-wind void (lambda () (sync never-evt)) stop)]
        [else (error 'serve "unknown transport ~a" transport)]))
    (lambda () (custodian-shutdown-all (runtime-custodian runtime)) (when store (close-store! store)))))
(define (manifest-diff before after)
  (define (key d)
    (if (eq? (hash-ref d 'kind) 'completion)
        (list 'completion (hash-ref d 'name) (hash-ref d 'argument))
        (cons (hash-ref d 'kind) (hash-ref d 'name))))
  (define old (for/hash ([d (in-list before)]) (values (key d) d)))
  (define new (for/hash ([d (in-list after)]) (values (key d) d)))
  (append (for/list ([(k d) (in-hash old)] #:unless (hash-has-key? new k)) (hasheq 'change "breaking-removal" 'declaration (format "~a" k)))
          (for/list ([(k d) (in-hash new)])
            (hasheq 'change (cond [(not (hash-has-key? old k)) "added"]
                                  [(equal? d (hash-ref old k)) "static-manifest-unchanged"] [else "review-required"])
                    'declaration (format "~a" k)))))
(define (main)
  (define transport "stdio") (define state #f) (define port 8000)
  (define args
    (command-line #:program "raco mcp"
      #:once-each [("--transport") value "stdio or http" (set! transport value)]
      [("--state") value "SQLite state file" (set! state value)]
      [("--port") value "HTTP port" (set! port (string->number value))]
      #:args args args))
  (unless (>= (length args) 2) (error 'mcp "usage: raco mcp [options] serve|inspect|diagram|docs|check|scenario|snapshot|diff module [other-module]"))
  (define command (car args)) (define path (cadr args))
  (case (string->symbol command)
    [(serve) (serve-interface (dynamic-require (module-path path) 'mcp-interface) #:transport transport #:state state #:port port)]
    [(inspect) (pretty-write (read-manifest path))]
    [(diagram) (display (manifest->mermaid (read-manifest path)))]
    [(docs) (printf "# Interface: ~a\n\n" (file-name-from-path path))
            (for ([d (in-list (read-manifest path))])
              (printf "## ~a `~a`\n\nSource: ~a:~a. Metadata requires runtime inspection.\n\n" (hash-ref d 'kind) (hash-ref d 'name) (hash-ref d 'source) (hash-ref d 'line)))]
    [(check) (parameterize ([current-namespace (make-base-namespace)])
               (expand (call-with-input-file path (lambda (in) (parameterize ([read-accept-reader #t]) (read-syntax path in))))))
             (displayln "Expansion checks passed.")]
    [(scenario) (dynamic-require `(submod ,(module-path path) test) #f)]
    [(snapshot) (define client (make-http-client path))
                (write-json (capture-snapshot (lambda (method params) (http-client-call client method params)))) (newline)]
    [(diff) (unless (= (length args) 3) (error 'diff "two module paths required"))
            (write-json (manifest-diff (read-manifest path) (read-manifest (caddr args)))) (newline)]
    [else (error 'mcp "unknown command ~a" command)]))
(module+ main (main))
