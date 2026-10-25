#lang racket/base

(provide (struct-out oauth-registration) (struct-out oauth-pending) (struct-out oauth-credential))
(struct oauth-registration (issuer client-id redirect-uri resource scopes) #:transparent)
(struct oauth-pending (registration metadata state verifier) #:transparent
  #:property prop:custom-write (lambda (_value out _mode) (display "#<oauth-pending>" out)))
(struct oauth-credential (issuer resource access-token refresh-token expires scopes) #:transparent
  #:property prop:custom-write (lambda (_value out _mode) (display "#<oauth-credential>" out)))
