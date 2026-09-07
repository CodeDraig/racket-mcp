#lang racket/base
(require rackunit racket/file racket/port racket/runtime-path racket/tcp mcp/scenario mcp/cli)
(define-runtime-path cli "../mcp/cli.rkt")
(define dir (make-temporary-file "mcp-scenarios-~a" 'directory))
(define (source name text)
  (define path (build-path dir name))
  (display-to-file text path #:exists 'truncate)
  path)
(define (run path)
  (parameterize ([current-output-port (open-output-string)] [current-error-port (open-output-string)])
    (run-scenarios path)))
(define (cli-result path)
  (define-values (process out in err)
    (subprocess #f #f #f (find-executable-path "racket") cli "scenario" path))
  (close-output-port in)
  (define output (box "")) (define errors (box ""))
  (define reader (thread (lambda () (set-box! output (port->string out)))))
  (define error-reader (thread (lambda () (set-box! errors (port->string err)))))
  (unless (sync/timeout 20 process)
    (subprocess-kill process #t)
    (error 'test "scenario CLI timed out"))
  (subprocess-wait process)
  (thread-wait reader) (thread-wait error-reader)
  (close-input-port out) (close-input-port err)
  (list (subprocess-status process) (unbox output) (unbox errors)))
(dynamic-wind void
  (lambda ()
    (define good
      (source "good.rkt"
        #<<MODULE
#lang mcp
(module+ test (require rackunit) (define helper-value 42))
(tool (outer) (text-result "outer"))
(module+ test
  (tool (test-only) (text-result "test-only"))
  (check-true (tool-descriptor? test-only))
  (check-equal? helper-value 42))
(define-syntax-rule (more-tests)
  (module+ test
    (check-equal? (map tool-descriptor-name (interface-descriptor-tools mcp-interface)) '("outer"))))
(more-tests)
(scenario sees-parent
  (check-equal? (map tool-descriptor-name (interface-descriptor-tools mcp-interface)) '("outer")))
(module* helper #f
  (provide names)
  (define names (map tool-descriptor-name (interface-descriptor-tools mcp-interface))))
(module* independent mcp/lang
  (tool (inner) (text-result "inner")))
(module plain racket/base (provide answer) (define answer 7))
MODULE
))
    (check-equal? (run good) '(0 . 4))
    (check-equal? (run good) '(0 . 4))
    (define path `(file ,(path->string good)))
    (check-equal? (dynamic-require `(submod ,path helper) 'names) '("outer"))
    (check-equal? (dynamic-require `(submod ,path plain) 'answer) 7)
    (define child (dynamic-require `(submod ,path independent) 'mcp-interface))
    ;; The explicitly selected child language owns an independent manifest.
    (check-equal? (map (lambda (entry) (hash-ref entry 'name)) (read-manifest good)) '(outer))
    (check-equal? (map (lambda (entry) (hash-ref entry 'name))
                      (dynamic-require `(submod ,path independent manifest) 'manifest)) '(inner))
    (define pass-cli (cli-result good))
    (check-equal? (car pass-cli) 0)
    (check-regexp-match #rx"4 tests passed" (cadr pass-cli))
    (check-equal? (caddr pass-cli) "")
    (define failed
      (source "failed.rkt"
        "#lang mcp\n(module+ test (require rackunit))\n(scenario false-assertion (check-equal? 1 2))\n"))
    (check-exn #rx"1 of 1 tests failed" (lambda () (run failed)))
    (define fail-cli (cli-result failed))
    (check-not-equal? (car fail-cli) 0)
    (check-regexp-match #rx"1 of 1 tests failed" (caddr fail-cli))
    (check-equal? (run good) '(0 . 4))
    (define exceptional
      (source "exception.rkt" "#lang mcp\n(scenario bad (error 'authored \"failed\"))\n"))
    (check-exn #rx"1 of 1 tests failed" (lambda () (run exceptional)))
    (check-not-equal? (car (cli-result exceptional)) 0)
    (define raw
      (source "raw.rkt" "#lang racket/base\n(module+ test (raise #f))\n"))
    (check-exn (lambda (value) (eq? value #f)) (lambda () (run raw)))
    (check-not-equal? (car (cli-result raw)) 0)
    (define missing (source "missing.rkt" "#lang racket/base\n"))
    (check-exn exn:fail? (lambda () (run missing)))
    (check-not-equal? (car (cli-result missing)) 0)
    ;; The runner tears down resources even after a caught assertion failure.
    (define port-file (build-path dir "port"))
    (define owned
      (source "owned.rkt"
        (format "#lang racket/base\n(require racket/tcp)\n(module+ test (require rackunit)\n (define listener (tcp-listen 0 4 #t \"127.0.0.1\"))\n (define-values (_a port _b _p) (tcp-addresses listener #t))\n (call-with-output-file ~s (lambda (out) (write port out)) #:exists 'truncate)\n (check-equal? 1 2))\n" (path->string port-file))))
    (check-exn #rx"1 of 1 tests failed" (lambda () (run owned)))
    (define port (call-with-input-file port-file read))
    (define listener (tcp-listen port 4 #t "127.0.0.1"))
    (check-true (tcp-listener? listener))
    (tcp-close listener))
  (lambda () (delete-directory/files dir)))
