#lang racket/base
(require mcp/storage mcp/oauth-registration-store mcp/oauth-registration mcp/json)
(module+ main
  (define args (current-command-line-arguments))
  (define store (open-sqlite-store (vector-ref args 0)))
  (define metadata (string->json (vector-ref args 1)))
  (define fields (string->json (vector-ref args 2)))
  (define result
    (ensure-oauth-registration! store metadata fields #:clock (lambda () 100) #:allow-loopback-http? #t
      #:register (lambda (_m _f)
                   (cond [(equal? (vector-ref args 3) "interrupt") (exit 9)]
                         [(equal? (vector-ref args 3) "interrupt-after-response")
                          (register-oauth-client! _m _f #:allow-loopback-http? #t)
                          (exit 9)]
                         [else (error 'worker "unexpected network registration")]))))
  (display (json->string (oauth-registration-result-metadata result)))
  (close-store! store))
