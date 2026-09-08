#lang racket/base
(require "json.rkt")
(provide current-build-identity call-with-build-identity)
;; A caller declaration, not evidence obtained from module or native-code
;; observation. Freeze mutable strings before retaining them in descriptors.
(define (normalize-build-identity value)
  (unless (or (not value) (and (string? value) (positive? (string-length value))))
    (raise-argument-error 'build-identity "#f or a nonempty application/runtime build identity" value))
  (and value (string->immutable-string value)))
(define current-build-identity (make-parameter #f normalize-build-identity))
(define (call-with-build-identity identity thunk)
  (unless identity (raise-argument-error 'call-with-build-identity "nonempty build identity" identity))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'call-with-build-identity "procedure accepting zero arguments" thunk))
  (parameterize ([current-build-identity identity]) (thunk)))
(define (bind-build-identity fingerprint [identity (current-build-identity)])
  (if identity
      (json->string (hasheq 'kind "declared-build/1" 'identity identity 'program fingerprint))
      fingerprint))
(define (fingerprint-build-identity fingerprint)
  ;; Legacy program fingerprints are arbitrary strings. Only our tagged envelope
  ;; contributes a declaration; ordinary version checks stay with the workflow.
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define value (string->json fingerprint))
    (and (hash? value) (equal? (hash-ref value 'kind #f) "declared-build/1")
         (let ([identity (hash-ref value 'identity #f)])
           (and (string? identity) identity)))))
(module* private #f (provide normalize-build-identity bind-build-identity fingerprint-build-identity))
