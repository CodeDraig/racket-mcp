#lang racket/base
(require mcp/authorization mcp/oauth)
(define fetches 0)
(define authorizer
  (make-oauth-authorizer
   #:resource "http://localhost:9999/mcp"
   #:redirect-uri "http://127.0.0.1:9876/callback"
   #:browse (lambda (_) (error 'probe "unexpected browser callback"))
   #:fetch (lambda (_) (set! fetches (add1 fetches)) (error 'probe "unexpected fetch"))))
(with-handlers ([exn:fail? (lambda (error)
                           (displayln (exn-message error))
                           (printf "Metadata fetches: ~a\n" fetches))])
  (authorize-resource! authorizer)
  (error 'probe "unexpected authorization success"))
