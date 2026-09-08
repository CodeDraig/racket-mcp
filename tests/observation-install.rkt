#lang racket/base
(require rackunit racket/file racket/port compiler/cm mcp/private/module-observation)
(define original-eval (current-eval))
(test-case "installation is idempotent and scoped observation restores its caller"
  (parameterize ([current-eval original-eval])
    (install-module-observation!)
    (define installed (current-eval))
    (install-module-observation!)
    (check-eq? (current-eval) installed)
    (call-with-module-observation
      (lambda ()
        (define nested (current-eval))
        (check-not-eq? nested installed)
        (install-module-observation!)
        (check-eq? (current-eval) nested)))
    (check-eq? (current-eval) installed)))
(test-case "installation preserves a caller evaluator and evaluates once"
  (parameterize ([current-eval original-eval])
    (define calls 0)
    (current-eval (lambda (expression) (set! calls (add1 calls)) (original-eval expression)))
    (install-module-observation!)
    (install-module-observation!)
    (parameterize ([current-namespace (make-base-namespace)])
      (check-equal? (eval '(+ 20 22)) 42))
    (check-equal? calls 1)))
(for* ([compiled? '(#f #t)] [preloaded? '(#f #t)] [mcp? '(#f #t)])
  (test-case (format "reader/language observation compiled=~a preloaded=~a mcp=~a" compiled? preloaded? mcp?)
    (define directory (make-temporary-file "mcp-observation-install-~a" 'directory))
    (define helper (build-path directory "helper.rkt"))
    (define language (build-path directory "language.rkt"))
    (define reader (build-path directory "reader.rkt"))
    (define application (build-path directory "application.rkt"))
    (dynamic-wind void
      (lambda ()
        (display-to-file "#lang racket/base\n(provide greeting)\n(define (greeting) \"old\")\n" helper)
        (display-to-file
          "#lang racket/base\n(require mcp/private/module-observation)\n(provide (all-from-out racket/base))\n(install-module-observation!)\n" language)
        (display-to-file
          "#lang s-exp syntax/module-reader\n\"language.rkt\"\n#:wrapper1 (lambda (read) (install-module-observation!) (read))\n(require mcp/private/module-observation)\n" reader)
        (display-to-file
          (string-append (if mcp? "#lang mcp\n" "#lang reader \"reader.rkt\"\n")
            "(require \"helper.rkt\")\n(provide result)\n(define result (greeting))\n") application)
        (when compiled?
          (for ([path (list helper language reader application)]) (managed-compile-zo path))
          (module-cache-clear!))
        (define namespace (make-base-namespace))
        (parameterize ([current-namespace namespace] [current-eval original-eval])
          (when preloaded? (dynamic-require helper #f))
          (check-equal? (dynamic-require application 'result) "old")
          (define observed (dynamic-require 'mcp/private/module-observation 'observed-module-code))
          (define identity (make-resolved-module-path helper))
          (define code (observed identity namespace))
          (if preloaded?
              ;; Already evaluated code must remain unknown; reading its file now
              ;; would not establish which implementation was actually loaded.
              (check-false code)
              (begin
                (check-true (compiled-module-expression? code))
                (check-equal? (module-compiled-name code) 'helper)))
          (display-to-file "#lang racket/base\n(provide greeting)\n(define (greeting) \"changed\")\n" helper #:exists 'truncate)
          (check-eq? (observed identity namespace) code)
          (check-equal? ((dynamic-require helper 'greeting)) "old")))
      (lambda () (delete-directory/files directory)))))
