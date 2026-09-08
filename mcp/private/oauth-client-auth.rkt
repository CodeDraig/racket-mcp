#lang racket/base
(provide (struct-out oauth-client-authentication))
;; Keep secrets out of the default printed representation.
(struct oauth-client-authentication (issuer client-id method secret)
  #:guard
  (lambda (issuer client-id method secret who)
    (for ([value (in-list (list issuer client-id))])
      (unless (and (string? value) (positive? (string-length value)))
        (raise-argument-error who "nonempty issuer and client ID strings" value)))
    (unless (memq method '(none client_secret_basic client_secret_post))
      (raise-argument-error who "supported OAuth client authentication method" method))
    (if (eq? method 'none)
        (when secret (error who "none authentication must not include a secret"))
        (unless (string? secret) (error who "client-secret authentication requires a secret string")))
    (values (string->immutable-string issuer) (string->immutable-string client-id)
            method (and secret (string->immutable-string secret)))))
