#lang racket/base
(require net/url "authorization.rkt" "oauth.rkt" "http.rkt")
(provide authorize-http-client!)
(define (authorize-http-client! client authorizer #:failure [failure #f]
                                #:scopes [scopes #f] #:reauthorize? [reauthorize? #f])
  (define resource (oauth-authorizer-resource authorizer))
  (define previous-token
    (call-with-semaphore (http-client-lock client)
      (lambda ()
        (unless (equal? (url->string (http-client-url client)) resource)
          (error 'authorize-http-client! "client URL does not match authorizer resource"))
        (and (http-client-token client) (string->immutable-string (http-client-token client))))))
  (when failure
    (unless (and (exn:fail:http:authorization? failure)
                 (equal? (exn:fail:http:authorization-resource failure) resource))
      (error 'authorize-http-client! "authorization failure belongs to a different resource")))
  (define credential
    (authorize-resource! authorizer
      #:challenges (if failure (exn:fail:http:authorization-challenges failure) '())
      #:rejected-token (and failure (exn:fail:http:authorization-request-token failure))
      #:scopes scopes #:reauthorize? reauthorize?))
  (define token (oauth-credential-access-token credential))
  (call-with-semaphore (http-client-lock client)
    (lambda ()
      ;; Application callbacks can change transport configuration. Never install
      ;; a credential onto a different endpoint or overwrite another new token.
      (unless (equal? (url->string (http-client-url client)) resource)
        (error 'authorize-http-client! "client URL changed during authorization"))
      (unless (or (equal? (http-client-token client) previous-token)
                  (equal? (http-client-token client) token))
        (error 'authorize-http-client! "client credential changed during authorization"))
      (set-http-client-token! client token)))
  credential)
