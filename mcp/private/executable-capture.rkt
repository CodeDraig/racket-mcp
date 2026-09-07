#lang racket/base
(require racket/list racket/port racket/runtime-path file/sha1 "executable-build.rkt")
(provide (struct-out module-code-capture) capture-module-export seal-module-code-capture!)

;; A capture is evidence about declarations actually evaluated under this loader,
;; not a hash of files that might differ from already loaded code. Unobserved
;; dependencies remain explicit; callers must not treat a partial capture as a
;; complete executable build fingerprint.
(struct module-code-capture (value observed unobserved build) #:transparent)
(define-namespace-anchor home)
(define-runtime-module-path-index build-module "executable-build.rkt")
(define (identity-name identity)
  (string->immutable-string (format "~s" (resolved-module-path-name identity))))
(define (module-source? expression)
  (and (syntax? expression)
       (pair? (syntax-e expression))
       (identifier? (car (syntax-e expression)))
       (eq? (syntax-e (car (syntax-e expression))) 'module)))
(define (capture-module-export path export #:namespace [namespace (make-base-namespace)])
  (define build (make-executable-build))
  (namespace-attach-module (namespace-anchor->namespace home)
                           (module-path-index-resolve build-module) namespace)
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
          (hash-set! observed (identity-name identity) (string->immutable-string digest)))
        (original-eval code)))
  (parameterize ([current-namespace namespace] [current-eval capture-eval] [current-executable-build build])
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
      (sort (hash-keys missing) string<?) build)))

;; Dependencies are explicit caller-supplied executable identities, not files
;; silently hashed after loading. No unobserved identity is trusted by default.
(define (seal-module-code-capture! capture #:dependencies [dependencies (hash)])
  (unless (and (hash? dependencies)
               (for/and ([(name fingerprint) (in-hash dependencies)])
                 (and (string? name) (string? fingerprint)
                      (positive? (string-length fingerprint)))))
    (raise-argument-error 'seal-module-code-capture! "map of module names to nonempty executable identities" dependencies))
  (define missing (filter (lambda (name) (not (hash-has-key? dependencies name)))
                          (module-code-capture-unobserved capture)))
  (unless (null? missing)
    (error 'seal-module-code-capture! "unobserved executable dependencies require explicit identities: ~s" missing))
  (define all
    (for/fold ([all (module-code-capture-observed capture)])
              ([name (in-list (module-code-capture-unobserved capture))])
      (hash-set all name (hash-ref dependencies name))))
  (define fingerprint
    (string-append "mcp-executable/1:"
      (bytes->hex-string
        (sha256-bytes (open-input-bytes
          (call-with-output-bytes
            (lambda (out)
              (write (list (version) (system-type 'vm) (system-type 'arch)
                           (for/list ([name (in-list (sort (hash-keys all) string<?))])
                             (list name (hash-ref all name)))) out))))))))
  (seal-executable-build! (module-code-capture-build capture) fingerprint)
  fingerprint)
