#lang racket/base
(require racket/path racket/port file/sha1 "private/module-observation.rkt" (only-in syntax/module-reader) "descriptor.rkt" "private/executable-capture.rkt" "private/module-imports.rkt" "private/module-identity.rkt")
(provide load-interface)
(define-namespace-anchor sdk-home)
(define sdk-language
  (module-path-index-resolve
   (module-path-index-join "lang.rkt" (variable-reference->module-path-index (#%variable-reference)))))
(define sdk-reader
  (module-path-index-resolve
   (module-path-index-join "lang/reader.rkt" (variable-reference->module-path-index (#%variable-reference)))))
(define module-name module-identity-key)
(define (bootstrap-identities)
  (define seen (make-hash))
  (define (visit identity)
    (define name (module-name identity))
    (unless (hash-has-key? seen name)
      (hash-set! seen name identity)
      (when (module-declared? identity #f)
        (for ([dependency (in-list (resolved-module-imports identity))])
          (visit dependency)))))
  (visit sdk-language)
  (visit sdk-reader)
  seen)
;; Prefer observed bootstrap code from the actual SDK registry. The caller owns
;; the immutable identity of any SDK/runtime code loaded before observation.
;; That identity never substitutes for an uncaptured application dependency.
(define (load-interface path #:runtime-build-id runtime-build-id)
  (unless (and (string? runtime-build-id) (positive? (string-length runtime-build-id)))
    (raise-argument-error 'load-interface "nonempty runtime build identity" runtime-build-id))
  (define application (if (path-string? path) (path->complete-path path) path))
  (define namespace (make-base-namespace))
  (define bootstrap
    (namespace-call-with-registry-lock (namespace-anchor->namespace sdk-home)
      (lambda ()
        (parameterize ([current-namespace (namespace-anchor->namespace sdk-home)])
          (dynamic-require sdk-language #f)
          (dynamic-require sdk-reader #f)
          (define identities (bootstrap-identities))
          ;; Sharing actual instances preserves descriptor types and SDK parameters.
          (namespace-attach-module (current-namespace) sdk-language namespace)
          (namespace-attach-module (current-namespace) sdk-reader namespace)
          identities))))
  (define capture (capture-module-export application 'mcp-interface #:namespace namespace))
  (unless (interface-descriptor? (module-code-capture-value capture))
    (error 'load-interface "module does not export an MCP interface descriptor"))
  (define dependencies
    (for/hash ([name (in-list (module-code-capture-unobserved capture))])
      (unless (or (hash-has-key? bootstrap name)
                  (member name (module-code-capture-predefined capture)))
        (error 'load-interface "application code was not captured; use a fresh loading process: ~a" name))
      (define identity (hash-ref bootstrap name #f))
      (define code
        (and identity
             (observed-module-code identity (namespace-anchor->namespace sdk-home))))
      (values name
        (if code
            (bytes->hex-string
             (sha256-bytes
              (open-input-bytes (call-with-output-bytes (lambda (out) (write code out))))))
            (string-append "explicit-runtime-build/1:" runtime-build-id)))))
  (void (seal-module-code-capture! capture #:dependencies dependencies))
  (module-code-capture-value capture))
