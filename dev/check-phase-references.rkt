#lang racket/base
(require racket/file racket/port racket/string)

;; An explicit release-gate probe, not an expected-failure unit test. Exit nonzero
;; if any advertised phase case fails. The syntax-spec cases do not import MCP.
(define language
  '(module checked racket/base
     (require mcp-syntax-spec-v3 (for-syntax racket/base))
     (provide define-checked)
     (syntax-spec
       (binding-class checked-name #:reference-compiler immutable-reference-compiler)
       (host-interface/definition
         (define-checked name:checked-name value:racket-expr)
         #:binding (export name)
         #:lhs [#'name]
         #:rhs [#'value]))))
(define (source sdk? phase)
  (define imports (if sdk? '(mcp) '((submod "." checked))))
  (define body
    (if sdk?
        '((schema Value String)
          (shape Record [label Value])
          (tool (echo [value Value]) (text-result value))
          (resource (document [id Value]) #:uri "document:///{id}" id)
          (prompt (choose [id Value]) (role "user" (text-content id)))
          (workflow (remember [value Value]) #:version "1"
            (checkpoint [saved Value] value)
            (text-result saved))
          (unless (and (equal? (Record-label (make-Record "ok")) "ok")
                       (equal? ((tool-descriptor-handler echo) (hasheq 'value "ok")) (text-result "ok"))
                       (equal? (resource-uri (document "ok")) "document:///ok")
                       (prompt-descriptor? choose)
                       (tool-descriptor? remember)
                       (eq? (let ([Value 'shadow]) Value) 'shadow))
            (error 'phase-probe "declaration behavior differs at shifted phase"))
          (displayln (hash-ref Value 'type)))
        '((define-checked Value 1)
          (unless (and (= Value 1) (eq? (let ([Value 'shadow]) Value) 'shadow))
            (error 'phase-probe "reference or lexical shadowing failed"))
          (displayln Value))))
  (append (if sdk? '() (list language))
          (if (zero? phase)
              `((require ,@imports) ,@body)
              `((require ,@(for/list ([level (in-range 1 (add1 phase))])
                              `(for-meta ,level racket/base))
                         (for-meta ,phase ,@imports))
                ,(for/fold ([form `(begin ,@body)]) ([_ (in-range phase)])
                   `(begin-for-syntax ,form))))))
(module+ main
  (define dir (make-temporary-file "mcp-phase-probe-~a" 'directory))
  (define failed? #f)
  (dynamic-wind void
    (lambda ()
      (for* ([sdk? '(#f #t)] [phase '(0 1 2)])
        (define name (format "~a-phase-~a" (if sdk? "mcp" "syntax-spec") phase))
        (define file (build-path dir (string-append name ".rkt")))
        (call-with-output-file file
          (lambda (out)
            (displayln "#lang racket/base" out)
            (for ([form (in-list (source sdk? phase))]) (write form out) (newline out))))
        (define-values (process out in err)
          (subprocess #f #f #f (find-executable-path "racket") file))
        (close-output-port in)
        (define timed-out? #f)
        (define watchdog
          (thread (lambda ()
                    (unless (sync/timeout 20 process)
                      (set! timed-out? #t)
                      (subprocess-kill process #t)))))
        (define output (port->string out))
        (define errors (port->string err))
        (subprocess-wait process)
        (thread-wait watchdog)
        (define status (subprocess-status process))
        (unless (and (zero? status) (not timed-out?)) (set! failed? #t))
        (printf "~a: ~a ~a\n" name (if timed-out? "timeout; exit" "exit") status)
        (unless (string=? output "") (display output))
        (unless (string=? errors "") (display errors))
        (close-input-port out) (close-input-port err)))
    (lambda () (delete-directory/files dir)))
  (when failed? (exit 1)))
