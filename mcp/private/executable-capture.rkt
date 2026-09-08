#lang racket/base
(require racket/list racket/port racket/runtime-path file/sha1 "executable-build.rkt" "module-imports.rkt" "module-identity.rkt" "module-code-tree.rkt" "compiled-identity.rkt" "native-executable.rkt")
(provide (struct-out module-code-capture) capture-module-export seal-module-code-capture!)

;; A capture records code evaluated under this loader or identities retained by
;; loaded declarations, never hashes of possibly replaced files. Unobserved
;; dependencies remain explicit; callers must not treat a partial capture as a
;; complete executable build fingerprint.
(struct module-code-capture (value observed unobserved build namespace resolver predefined) #:transparent)
(define-namespace-anchor home)
(define-runtime-module-path-index build-module "executable-build.rkt")
(define identity-name module-identity-key)
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
  (define identities (make-hash))
  (define imports (make-hash))
  (define original-resolver (current-module-name-resolver))
  (define (module-dependencies identity)
    (if (module-declared? identity #f)
        (resolved-module-imports identity)
        '()))
  (define original-eval (current-eval))
  (define (capture-eval expression)
    ;; Compile a source module exactly once and evaluate that same object. The
    ;; default compiled-file loader already supplies a compiled module object.
    (define code (if (module-source? expression) (compile expression) expression))
    (define declared (current-module-declare-name))
    (define identity
      (and declared (if (compiled-module-expression? code)
                        (module-code-identity declared code) declared)))
    (if (and identity (compiled-module-expression? code))
        (begin0 (original-eval code)
          ;; Traverse imports from evaluated roots and their actual references.
          ;; Unused nested declarations (such as configure-runtime) are recorded
          ;; code, but their unrequested imports are not loaded dependencies.
          (hash-set! identities (identity-name identity) identity)
          (for ([entry (in-list (module-code-tree identity code))])
            (define identity (car entry))
            (define name (identity-name identity))
            (define digest
              (or (compiled-module-producer-identity (cdr entry))
                  (bytes->hex-string
                    (sha256-bytes
                      (open-input-bytes
                        (call-with-output-bytes (lambda (out) (write (cdr entry) out))))))))
            (hash-set! observed name (string->immutable-string digest))
            ;; Preserve imports in their declaration namespace, including modules
            ;; loaded dynamically while the application is instantiated.
            (hash-set! imports name (module-dependencies identity))))
        (original-eval code)))
  (parameterize ([current-namespace namespace] [current-eval capture-eval] [current-executable-build build])
    (define value (dynamic-require path export))
    (define root (module-path-index-resolve (module-path-index-join path #f)))
    (define visited (make-hash))
    (define missing (make-hash))
    (define predefined (make-hash))
    (define (visit identity)
      (define name (identity-name identity))
      (unless (hash-ref visited name #f)
        (hash-set! visited name #t)
        (when (module-predefined? identity) (hash-set! predefined name #t))
        (unless (hash-has-key? observed name)
          (define retained
            (and (module-declared? identity #f)
                 (declared-module-producer-identity identity)))
          (if retained
              (hash-set! observed name retained)
              (hash-set! missing name #t)))
        (for ([dependency (in-list (hash-ref imports name (lambda () (module-dependencies identity))))])
          (visit dependency))))
    (visit root)
    (for ([identity (in-hash-values identities)]) (visit identity))
    (module-code-capture value
      (for/hash ([(name digest) (in-hash observed)]) (values name digest))
      (sort (hash-keys missing) string<?) build namespace original-resolver
      (sort (hash-keys predefined) string<?))))

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
    (string-append "mcp-executable/2:"
      (bytes->hex-string
        (sha256-bytes (open-input-bytes
          (call-with-output-bytes
            (lambda (out)
              (write (list (version) (system-type 'vm) (system-type 'arch)
                           (running-executable-identity)
                           (for/list ([name (in-list (sort (hash-keys all) string<?))])
                             (list name (hash-ref all name)))) out))))))))
  (define namespace (module-code-capture-namespace capture))
  (define resolver (module-code-capture-resolver capture))
  (define guard
    (case-lambda
      [(identity origin)
       (error 'workflow "module declarations cannot be attached during sealed execution: ~a"
              (identity-name identity))]
      [(path relative source load?)
       (define identity (resolver path relative source #f))
       (when load?
         (unless (and (hash-has-key? all (identity-name identity))
                      (module-declared? identity #f))
           (error 'workflow "module was not loaded in the sealed executable: ~a"
                  (identity-name identity))))
       (if load? (resolver path relative source #t) identity)]))
  (seal-executable-build! (module-code-capture-build capture) fingerprint
    #:runner (lambda (thunk)
               (parameterize ([current-namespace namespace]
                              [current-module-name-resolver guard])
                 (thunk))))
  fingerprint)
