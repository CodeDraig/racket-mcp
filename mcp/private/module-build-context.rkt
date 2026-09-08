#lang racket/base
(require "executable-build.rkt" "declared-code-capture.rkt" "executable-capture.rkt"
         "module-finalization.rkt" racket/splicing racket/stxparam
         (for-syntax racket/base syntax/parse racket/stxparam))
(provide with-module-build-context with-enclosing-module-build-context
         module-begin/build-context module-build-context-build
         module-build-context-capture module-build-context-initialized? seal-module-build-context!)

(struct context (build owned? root namespace capture captured? initialized? lock) #:mutable)
(define (make-context reference)
  (define inherited (current-executable-build))
  (context (or inherited (make-executable-build)) (not inherited)
           (variable-reference->resolved-module-path reference)
           (variable-reference->namespace reference) #f #f #f (make-semaphore 1)))
(define (module-build-context-build ctx) (context-build ctx))
(define (module-build-context-capture ctx)
  (call-with-semaphore (context-lock ctx) (lambda () (context-capture ctx))))
(define (module-build-context-initialized? ctx)
  (call-with-semaphore (context-lock ctx) (lambda () (context-initialized? ctx))))
(define-syntax-parameter enclosing-module-context (lambda (_) #'#f))
;; Only the trusted final expression of module-begin/build-context calls this.
;; It runs after all expanded body forms, including recursively lifted forms.
(define (finish-context! ctx)
  (call-with-semaphore (context-lock ctx)
    (lambda ()
      (when (context-initialized? ctx)
        (error 'module-begin/build-context "module context was already finalized"))
      (when (context-owned? ctx)
        (parameterize ([current-namespace (context-namespace ctx)])
          (when (module-declared? (context-root ctx) #f)
            (set-context-capture! ctx
              (capture-declared-module-code (context-root ctx)
                #:namespace (context-namespace ctx) #:build (context-build ctx)))))
        (set-context-captured?! ctx #t))
      (set-context-initialized?! ctx #t))))
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
;; Legacy callers certify that their original loading operation returned.
;; Compiler-managed callers require the final initialization marker instead.
;; A prior snapshot or repeated dynamic-require alone cannot certify success.
;; Neither kind of capture seals or authorizes execution by itself.
(define (seal-module-build-context! ctx #:dependencies [dependencies (hash)]
                                   #:require-initialized? [require-initialized? #f])
  (call-with-semaphore (context-lock ctx)
    (lambda ()
      (when (and require-initialized? (not (context-initialized? ctx)))
        (error 'seal-module-build-context! "module initialization has not completed"))
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
     (define enclosing (syntax-parameter-value #'enclosing-module-context))
     (define lifted
       (if (rename-transformer? enclosing)
           (rename-transformer-target enclosing)
           (syntax-local-lift-expression #'(make-context (#%variable-reference)))))
     (unless (rename-transformer? enclosing)
       (syntax-local-lift-module-end-declaration #`(capture-context! #,lifted)))
     #`(let ([name #,lifted])
         (parameterize ([current-executable-build
                         (or (current-executable-build) (module-build-context-build name))])
           body))]))

;; One lexical context per module, shared by construction sites and factories.
;; An enclosing explicit loader still owns sealing of its inherited build.
(define-syntax (module-begin/build-context stx)
  (syntax-parse stx
    [(_ (~optional (~seq #:module-begin original:id)
                   #:defaults ([original #'#%plain-module-begin]))
        body ...)
     (define ctx (car (generate-temporaries '(module-context))))
     #`(module-begin/finish #:finish (finish-context! #,ctx)
                          #:module-begin original
         (define #,ctx (make-context (#%variable-reference)))
         (splicing-syntax-parameterize
           ([enclosing-module-context (make-rename-transformer (quote-syntax #,ctx))])
           body ...))]))

;; Generated declarations use the module's context when this compiler boundary
;; is installed. Ordinary library clients keep their explicit construction scope.
(define-syntax (with-enclosing-module-build-context stx)
  (syntax-parse stx
    [(_ body:expr)
     (if (rename-transformer? (syntax-parameter-value #'enclosing-module-context))
         #'(with-module-build-context ignored body)
         #'body)]))
