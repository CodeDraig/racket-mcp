#lang racket/base
(require net/url)
(provide current-oauth-loopback-http? oauth-secure-url?)
(define current-oauth-loopback-http? (make-parameter #f))
(define (oauth-secure-url? u #:loopback? [loopback? (current-oauth-loopback-http?)])
  (and (url-host u) (not (url-user u)) (not (url-fragment u))
       (or (equal? (url-scheme u) "https")
           (and loopback? (equal? (url-scheme u) "http")
                (member (string-downcase (url-host u)) '("localhost" "127.0.0.1" "::1"))))))
