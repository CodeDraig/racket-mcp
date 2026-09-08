#lang racket/base
(require rackunit racket/runtime-path racket/file compiler/cm mcp/private/module-build-context
         mcp/private/executable-build mcp/private/executable-capture mcp/workflow mcp/schema)
(module application racket/base
  (require mcp/private/module-build-context mcp/workflow mcp/schema)
  (provide ctx program before-finished early-seal)
  (define before-finished #f)
  (define early-seal #f)
  (define pair
    (with-module-build-context build
      (begin
        (set! before-finished (module-build-context-capture build))
        (set! early-seal (with-handlers ([exn:fail? exn-message]) (seal-module-build-context! build)))
        (cons build (make-workflow "flow" "1" "source"
                     (list (workflow-stage 'done 'complete Any (lambda (_) "done") #f #f)))))))
  (define ctx (car pair))
  (define program (cdr pair)))
(module inherited racket/base
  (require mcp/private/module-build-context mcp/private/executable-build)
  (provide ctx factory)
  (define ctx (with-module-build-context build build))
  (define (factory) (with-module-build-context build (current-executable-build))))
(module shared racket/base
  (provide escaped)
  (define escaped (box #f)))
(module broken racket/base
  (require mcp/private/module-build-context (submod ".." shared))
  (with-module-build-context build (set-box! escaped build))
  (error 'broken "initialization aborted"))
(module broken-late racket/base
  (require mcp/private/module-build-context (submod ".." shared)
           (for-syntax racket/base))
  (with-module-build-context build (set-box! escaped build))
  (define-syntax (fail-later stx)
    (syntax-local-lift-module-end-declaration #'(error 'late "later module end failed"))
    #'(void))
  (fail-later))
(require (submod "." shared))
(define-runtime-path self "module-build-context.rkt")
(test-case "module end freezes the build and explicit sealing remains required"
  (define ctx (dynamic-require `(submod ,self application) 'ctx))
  (define program (dynamic-require `(submod ,self application) 'program))
  (check-false (dynamic-require `(submod ,self application) 'before-finished))
  (check-regexp-match #rx"capture point has not been reached" (dynamic-require `(submod ,self application) 'early-seal))
  (define capture (module-build-context-capture ctx))
  (check-true (module-code-capture? capture))
  (check-eq? (module-build-context-build ctx) (module-code-capture-build capture))
  (check-exn #rx"not sealed" (lambda () (workflow-executable-fingerprint program (hasheq))))
  (define dependencies (for/hash ([name (in-list (module-code-capture-unobserved capture))])
                         (values name "explicit-test-build/1")))
  (void (seal-module-build-context! ctx #:dependencies dependencies))
  (check-true (string? (workflow-executable-fingerprint program (hasheq))))
  (check-exn #rx"already sealed" (lambda () (seal-module-build-context! ctx #:dependencies dependencies))))
(test-case "an explicit enclosing loader retains ownership including later factories"
  (define build (make-executable-build))
  (define ctx
    (parameterize ([current-executable-build build])
      (dynamic-require `(submod ,self inherited) 'ctx)))
  (check-eq? (module-build-context-build ctx) build)
  (check-false (module-build-context-capture ctx))
  (check-exn #rx"enclosing loader owns" (lambda () (seal-module-build-context! ctx)))
  (define factory (dynamic-require `(submod ,self inherited) 'factory))
  (check-eq? (factory) build)
  (define override (make-executable-build))
  (parameterize ([current-executable-build override])
    (check-eq? (factory) override)))
(test-case "failure before the capture point leaves an escaped context uncaptured"
  (check-exn #rx"initialization aborted" (lambda () (dynamic-require `(submod ,self broken) #f)))
  (define ctx (unbox escaped))
  (check-false (module-build-context-capture ctx))
  (check-exn #rx"capture point has not been reached" (lambda () (seal-module-build-context! ctx)))
  (check-exn #rx"not sealed" (lambda () (executable-build-fingerprint (module-build-context-build ctx)))))
(test-case "phase-shifted construction defers until compiled code is declared"
  (define directory (make-temporary-file "mcp-context-phase-~a" 'directory))
  (define (at-phase phase body)
    (if (zero? phase) body `(begin-for-syntax ,(at-phase (sub1 phase) body))))
  (dynamic-wind void
    (lambda ()
      (for ([phase '(1 2)])
        (define provider (build-path directory (format "provider-~a.rkt" phase)))
        (define imports
          (for/list ([level (in-range 1 (add1 phase))])
            `(for-meta ,level racket/base mcp/private/module-build-context
                       mcp/private/executable-capture)))
        (call-with-output-file provider
          (lambda (out)
            (displayln "#lang racket/base" out)
            (write `(require ,@imports) out) (newline out)
            (write (at-phase phase '(define ctx (with-module-build-context build build))) out)
            (newline out)
            (write `(provide (for-meta ,phase ctx)) out) (newline out)))
        (managed-compile-zo provider)
        (parameterize ([current-namespace (make-base-namespace)])
          (eval `(module consumer racket/base
                   (require (file ,(path->string provider)) ,@imports)
                   ,(at-phase phase
                      `(unless (and (module-build-context-capture ctx)
                                    (= (namespace-base-phase
                                         (module-code-capture-namespace (module-build-context-capture ctx)))
                                       ,phase))
                         (error 'test "compiled context was not finalized at its phase"))))))))
    (lambda () (delete-directory/files directory))))

(test-case "a later module-end failure does not seal an earlier capture"
  (check-exn #rx"later module end failed"
    (lambda () (dynamic-require `(submod ,self broken-late) #f)))
  (define ctx (unbox escaped))
  (check-true (module-code-capture? (module-build-context-capture ctx)))
  (check-exn #rx"not sealed"
    (lambda () (executable-build-fingerprint (module-build-context-build ctx)))))
