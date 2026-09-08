#lang racket/base
(require racket/list racket/port file/sha1
         "module-observation.rkt" "compiled-identity.rkt" "module-identity.rkt"
         "module-imports.rkt" "executable-build.rkt" "executable-capture.rkt")
(provide capture-declared-module-code)

;; Freeze evidence already available in this registry. No source file is read,
;; module instantiated, or user export obtained. Observed dynamic declarations
;; are included conservatively; unobserved static dependencies remain explicit.
;; This is a module-code snapshot, not proof about arbitrary ambient closures.
(define (capture-declared-module-code root
                                      #:namespace [namespace (current-namespace)]
                                      #:build [build (make-executable-build)]
                                      #:value [value #f])
  (unless (resolved-module-path? root)
    (raise-argument-error 'capture-declared-module-code "resolved-module-path?" root))
  (namespace-call-with-registry-lock namespace
    (lambda ()
      (parameterize ([current-namespace namespace])
        (unless (module-declared? root #f)
          (error 'capture-declared-module-code "module is not declared: ~a" root))
        (define snapshot (module-observation-snapshot namespace))
        (define observed (make-hash))
        (define missing (make-hash))
        (define predefined (make-hash))
        (define visited (make-hash))
        (define (visit identity)
          (define name (module-identity-key identity))
          (unless (hash-has-key? visited name)
            (hash-set! visited name #t)
            (when (module-predefined? identity) (hash-set! predefined name #t))
            (define code (hash-ref snapshot identity #f))
            (define digest
              (if code
                  (or (compiled-module-producer-identity code)
                      (bytes->hex-string
                        (sha256-bytes
                          (open-input-bytes
                            (call-with-output-bytes (lambda (out) (write code out)))))))
                  (and (module-declared? identity #f)
                       (declared-module-producer-identity identity))))
            (if digest (hash-set! observed name (string->immutable-string digest))
                (hash-set! missing name #t))
            (when (module-declared? identity #f)
              (for ([dependency (in-list (resolved-module-imports identity))])
                (visit dependency)))))
        (visit root)
        (for ([identity (in-hash-keys snapshot)] #:when (module-declared? identity #f))
          (visit identity))
        (module-code-capture value
          (for/hash ([(name digest) (in-hash observed)]) (values name digest))
          (sort (hash-keys missing) string<?) build namespace
          (current-module-name-resolver) (sort (hash-keys predefined) string<?))))))
