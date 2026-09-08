#lang racket/base
(require "executable-build.rkt" "declared-code-capture.rkt" "executable-capture.rkt"
         (for-syntax racket/base syntax/parse))
(provide with-module-build-context module-build-context-build
         module-build-context-capture seal-module-build-context!)

(struct context (build owned? root namespace capture captured? lock) #:mutable)
(define (make-context reference)
  (define inherited (current-executable-build))
  (context (or inherited (make-executable-build)) (not inherited)
           (variable-reference->resolved-module-path reference)
           (variable-reference->namespace reference) #f #f (make-semaphore 1)))
(define (module-build-context-build ctx) (context-build ctx))
(define (module-build-context-capture ctx)
  (call-with-semaphore (context-lock ctx) (lambda () (context-capture ctx))))
(define (capture-context! ctx)
  (when (context-owned? ctx)
    (call-with-semaphore (context-lock ctx)
      (lambda ()
        (unless (context-captured? ctx)
          ;; A begin-for-syntax body can execute before its enclosing module
          ;; has a declaration. Do not freeze a partial expansion as code.
          (parameterize ([current-namespace (context-namespace ctx)])
            (when (module-declared? (context-root ctx) #f)
              (set-context-capture! ctx
                (capture-declared-module-code (context-root ctx)
                  #:namespace (context-namespace ctx) #:build (context-build ctx)))))
          (set-context-captured?! ctx #t))))))
;; Call only after the original module-loading operation returned successfully.
;; A module-end snapshot is not proof of successful initialization: a later
;; lifted expression can still fail, and retrying dynamic-require cannot certify
;; the original load. Capturing never seals or authorizes execution by itself.
(define (seal-module-build-context! ctx #:dependencies [dependencies (hash)])
  (call-with-semaphore (context-lock ctx)
    (lambda ()
      (unless (context-owned? ctx)
        (error 'seal-module-build-context! "the enclosing loader owns this build"))
      (unless (context-captured? ctx)
        (error 'seal-module-build-context! "module build capture point has not been reached"))
      (unless (context-capture ctx)
        (error 'seal-module-build-context! "declared code is unavailable during expansion; load the compiled module before sealing"))
      (seal-module-code-capture! (context-capture ctx) #:dependencies dependencies))))

;; The lifted binding belongs to this module/phase, not a transformer registry.
;; A factory invoked after module loading keeps its original enclosing build;
;; an explicitly active capture can still provide the construction context.
(define-syntax (with-module-build-context stx)
  (syntax-parse stx
    [(_ name:id body:expr)
     (unless (syntax-transforming-module-expression?)
       (raise-syntax-error #f "requires a module context" stx))
     (define lifted (syntax-local-lift-expression #'(make-context (#%variable-reference))))
     (syntax-local-lift-module-end-declaration #`(capture-context! #,lifted))
     #`(let ([name #,lifted])
         (parameterize ([current-executable-build
                         (or (current-executable-build) (module-build-context-build name))])
           body))]))
