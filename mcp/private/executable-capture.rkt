#lang racket/base
(require racket/list racket/port file/sha1)
(provide (struct-out module-code-capture) capture-module-export)

;; A capture is evidence about declarations actually evaluated under this loader,
;; not a hash of files that might differ from already loaded code. Unobserved
;; dependencies remain explicit; callers must not treat a partial capture as a
;; complete executable build fingerprint.
(struct module-code-capture (value observed unobserved) #:transparent)
(define (identity-name identity)
  (format "~s" (resolved-module-path-name identity)))
(define (module-source? expression)
  (and (syntax? expression)
       (pair? (syntax-e expression))
       (identifier? (car (syntax-e expression)))
       (eq? (syntax-e (car (syntax-e expression))) 'module)))
(define (capture-module-export path export #:namespace [namespace (make-base-namespace)])
  (define observed (make-hash))
  (define original-eval (current-eval))
  (define (capture-eval expression)
    ;; Compile a source module exactly once and evaluate that same object. The
    ;; default compiled-file loader already supplies a compiled module object.
    (define code (if (module-source? expression) (compile expression) expression))
    (define identity (current-module-declare-name))
    (define digest
      (and identity (compiled-module-expression? code)
           (bytes->hex-string
            (sha256-bytes
             (open-input-bytes (call-with-output-bytes (lambda (out) (write code out))))))))
    (if digest
        (begin0 (original-eval code)
          (hash-set! observed (identity-name identity) digest))
        (original-eval code)))
  (parameterize ([current-namespace namespace] [current-eval capture-eval])
    (define value (dynamic-require path export))
    (define root (module-path-index-resolve (module-path-index-join path #f)))
    (define visited (make-hash))
    (define missing (make-hash))
    (define (visit identity)
      (define name (identity-name identity))
      (unless (hash-ref visited name #f)
        (hash-set! visited name #t)
        (unless (hash-has-key? observed name) (hash-set! missing name #t))
        (when (module-declared? identity #f)
          (for* ([phase-imports (in-list (module->imports identity))]
                 [dependency (in-list (cdr phase-imports))])
            (visit (module-path-index-resolve dependency))))))
    (visit root)
    (module-code-capture value
      (for/hash ([(name digest) (in-hash observed)]) (values name digest))
      (sort (hash-keys missing) string<?))))
