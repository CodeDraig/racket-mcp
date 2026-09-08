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
(module* private #f (provide normalize-build-identity bind-build-identity))
