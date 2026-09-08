#lang racket/base
(require rackunit racket/file racket/path racket/port compiler/cm mcp/private/compiled-identity)
(define compiler (current-compile))
(define (module-syntax datum) (namespace-syntax-introduce (datum->syntax #f datum)))
(define (program value)
  (module-syntax `(module application racket/base
    (require (for-syntax racket/base))
    (begin-for-syntax (displayln "EXPAND"))
    (provide value) (define value ,value) (displayln "RUN")
    (module child racket/base (provide value) (define value "child")))))
(define (build value)
  (parameterize ([current-namespace (make-base-namespace)])
    (define code #f)
    (check-equal? (with-output-to-string
      (lambda () (set! code (compile-with-module-identity (program value) #f compiler)))) "EXPAND\n")
    code))
(test-case "single compiler call, changed bodies, declaration-only inspection"
  (parameterize ([current-namespace (make-base-namespace)])
    (define calls 0)
    (define code #f)
    (check-equal? (with-output-to-string
      (lambda () (set! code (compile-with-module-identity (program "old") #t
        (lambda (source immediate?) (check-false immediate?)
          (set! calls (add1 calls)) (compiler source immediate?)))))) "EXPAND\n")
    (check-equal? calls 1)
    (define id (compiled-module-producer-identity code))
    (check-regexp-match #px"^mcp-compiled/1:[0-9a-f]{64}$" id)
    (check-not-equal? id (compiled-module-producer-identity (build "new")))
    (eval code)
    (check-equal? (with-output-to-string
      (lambda () (check-equal? (declared-module-producer-identity (make-resolved-module-path 'application)) id))) "")
    (check-equal? (dynamic-require '(submod 'application child) 'value) "child")
    (check-equal? (with-output-to-string
      (lambda () (check-equal? (dynamic-require ''application 'value) "old"))) "RUN\n")))
(for ([replace? '(#f #t)])
  (test-case (format "loaded identity survives artifact ~a" (if replace? 'replacement 'deletion))
    (define dir (make-temporary-file "mcp-identity-files-~a" 'directory))
    (define source (build-path dir "application.rkt"))
    (define artifact (build-path dir "compiled" "application_rkt.zo"))
    (define (write-build value)
      (define code (build value))
      (display-to-file "#lang racket/base\n" source #:exists 'truncate)
      (make-directory* (path-only artifact))
      (call-with-output-file artifact (lambda (out) (write code out)) #:exists 'truncate)
      (compiled-module-producer-identity code))
    (dynamic-wind void
      (lambda ()
        (define id (write-build "old"))
        (parameterize ([current-namespace (make-base-namespace)]
                       [current-compiled-file-roots '(same)])
          ;; Visit compile-time bindings without instantiating the application.
          (check-equal? (with-output-to-string (lambda () (dynamic-require source (void)))) "EXPAND\n")
          (define identity (make-resolved-module-path source))
          (if replace? (check-not-equal? id (write-build "new")) (delete-directory/files dir))
          (check-equal? (declared-module-producer-identity identity) id)
          (check-equal? (with-output-to-string
            (lambda () (check-equal? (dynamic-require identity 'value) "old"))) "RUN\n")))
      (lambda () (when (directory-exists? dir) (delete-directory/files dir))))))
(test-case "language information delegates without invoking application code"
  (parameterize ([current-namespace (make-base-namespace)])
    (eval '(module information racket/base (provide get-info)
      (define (get-info data) (lambda (key default) (if (eq? key 'answer) data default)))))
    (define source (syntax-property (module-syntax '(module application racket/base))
      'module-language '#((quote information) get-info 42)))
    (define code (compile-with-module-identity source #f compiler))
    (define info (module-compiled-language-info code))
    (define lookup
      ((dynamic-require (vector-ref info 0) (vector-ref info 1)) (vector-ref info 2)))
    (check-equal? (lookup 'mcp-executable-identity #f) (compiled-module-producer-identity code))
    (check-equal? (lookup 'answer #f) 42)
    (check-equal? (lookup 'other 'fallback) 'fallback)))
(test-case "non-modules pass through and dropped metadata is rejected"
  (parameterize ([current-namespace (make-base-namespace)])
    (check-equal? (eval (compile-with-module-identity '(+ 20 22) #f compiler)) 42)
    (check-exn #rx"discarded producer metadata"
      (lambda () (compile-with-module-identity (module-syntax '(module application racket/base)) #f
        (lambda (source immediate?) (compiler (syntax-property source 'module-language #f) immediate?)))))
    (check-false (compiled-module-producer-identity (compile '(module plain racket/base)))))
  (check-exn exn:fail:contract? (lambda () (declared-module-producer-identity 'not-resolved))))

(for ([compiled? '(#f #t)])
  (test-case (format "actual MCP module retains identity after file deletion, compiled=~a" compiled?)
    (define dir (make-temporary-file "mcp-identity-language-~a" 'directory))
    (define application (build-path dir "application.rkt"))
    (dynamic-wind void
      (lambda ()
        (display-to-file "#lang mcp\n(provide result)\n(define result 42)\n(displayln \"RUN\")\n" application)
        (parameterize ([current-compile compiler])
          (when compiled? (managed-compile-zo application) (module-cache-clear!))
          (parameterize ([current-namespace (make-base-namespace)])
            (check-equal? (with-output-to-string (lambda () (dynamic-require application (void)))) "")
            (define id (declared-module-producer-identity (make-resolved-module-path application)))
            (check-regexp-match #px"^mcp-compiled/1:[0-9a-f]{64}$" id)
            (delete-directory/files dir)
            (check-equal? (declared-module-producer-identity (make-resolved-module-path application)) id)
            (check-equal? (with-output-to-string
              (lambda () (check-equal? (dynamic-require application 'result) 42))) "RUN\n"))))
      (lambda () (when (directory-exists? dir) (delete-directory/files dir))))))

(test-case "identity lookup cannot load an undeclared file"
  (define dir (make-temporary-file "mcp-identity-unloaded-~a" 'directory))
  (define source (build-path dir "unloaded.rkt"))
  (dynamic-wind void
    (lambda ()
      (display-to-file "#lang racket/base\n(error 'application \"must not instantiate\")\n" source)
      (parameterize ([current-namespace (make-base-namespace)])
        (define identity (make-resolved-module-path source))
        (check-exn exn:fail? (lambda () (declared-module-producer-identity identity)))
        (check-false (module-declared? identity #f))))
    (lambda () (delete-directory/files dir))))
