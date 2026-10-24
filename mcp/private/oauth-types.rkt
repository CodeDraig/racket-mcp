#lang racket/base

(provide (struct-out oauth-registration) (struct-out oauth-pending) (struct-out oauth-credential))
(struct oauth-registration (issuer client-id redirect-uri resource scopes) #:transparent)
(struct oauth-pending (registration metadata state verifier) #:transparent)
(struct oauth-credential (issuer resource access-token refresh-token expires scopes) #:transparent)
