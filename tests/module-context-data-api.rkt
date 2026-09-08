#lang racket/base
(require rackunit racket/runtime-path mcp/private/module-build-context
         mcp/private/executable-build mcp/private/executable-capture
         mcp/workflow mcp/storage)
(module language racket/base
  (require mcp/private/module-build-context)
  (provide (except-out (all-from-out racket/base) #%module-begin)
           (rename-out [module-begin/build-context #%module-begin])))
(module application (submod ".." language)
  (require mcp/private/module-build-context mcp/private/executable-build
           mcp/workflow mcp/schema (for-syntax racket/base))
  (provide context direct indirect left right late evaluations order)
  (define context (with-module-build-context ctx ctx))
  (define evaluations 0)
  (define order '())
  (define (construct name)
    (set! evaluations (add1 evaluations))
    (set! order (append order (list name)))
    (make-workflow name "1" "fixture"
      (list (workflow-stage 'done 'complete Any (lambda (_) name) #f #f))))
  (define direct (make-workflow "direct" "1" "fixture"
                   (list (workflow-stage 'done 'complete Any (lambda (_) "direct") #f #f))))
  (define indirect (construct "indirect"))
  (define-values (left right) (values (construct "left") (construct "right")))
  (define late #f)
  (define-syntax (lift stx)
    (syntax-local-lift-module-end-declaration #'(set! late (construct "late")))
    #'(void))
  (lift))
(define-runtime-path self "module-context-data-api.rkt")
(test-case "ordinary constructors and lifted host calls share the module build"
  (define (get name) (dynamic-require `(submod ,self application) name))
  (define ctx (get 'context))
  (define programs (map get '(direct indirect left right late)))
  (check-equal? (get 'evaluations) 4)
  (check-equal? (get 'order) '("indirect" "left" "right" "late"))
  (check-true (module-build-context-initialized? ctx))
  (for ([program (in-list programs)])
    (check-exn #rx"not sealed" (lambda () (workflow-executable-fingerprint program (hasheq)))))

  (define capture (module-build-context-capture ctx))
  (void (seal-module-build-context! ctx #:require-initialized? #t
          #:dependencies (for/hash ([name (in-list (module-code-capture-unobserved capture))])
                           (values name "explicit-test-fixture-build/1"))))
  (define store (open-memory-store))
  (dynamic-wind void
    (lambda ()
      (for ([program (in-list programs)] [expected '("direct" "indirect" "left" "right" "late")])
        (check-equal? (run-workflow program store (hasheq) #:principal "fixture") expected))
      (check-equal? (get 'evaluations) 4))
    (lambda () (close-store! store))))

(module failed (submod ".." language)
  (error 'fixture "initialization failed"))
(test-case "failed initialization restores the caller's build parameter"
  (define before (current-executable-build))
  (check-exn #rx"initialization failed"
    (lambda () (dynamic-require `(submod ,self failed) #f)))
  (check-eq? (current-executable-build) before))

(module invalid-language racket/base
  (require mcp/private/module-finalization mcp/private/executable-build
           (for-syntax racket/base))
  (provide (except-out (all-from-out racket/base) #%module-begin)
           (rename-out [body #%module-begin]))
  (define-syntax-rule (body form ...)
    (module-begin/finish #:finish (void)
                        #:parameterize ([current-executable-build #f])
                        #:exclude (missing-acquisition)
                        form ...)))
(test-case "a missing acquisition cannot silently disable initialization scope"
  (check-exn #rx"unresolved acquisition bindings"
    (lambda ()
      (eval #`(module invalid-scope (submod (file #,(path->string self)) invalid-language)
                (void))))))
