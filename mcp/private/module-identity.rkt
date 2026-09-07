#lang racket/base
(provide module-identity-key)
;; A printed fresh/unreadable symbol is not a portable module identity: distinct
;; symbols can print like the same predefined module or each other. File paths
;; and ordinary reader/interned symbolic names retain their existing encoding.
(define (module-identity-key identity)
  (define name (resolved-module-path-name identity))
  (define (check-name part)
    (cond [(symbol? part)
           (unless (symbol-interned? part)
             (error 'executable-identity
                    "non-interned module identity requires explicit portable provenance: ~s" name))]
          [(pair? part) (for-each check-name part)]))
  (check-name name)
  (string->immutable-string (format "~s" name)))
