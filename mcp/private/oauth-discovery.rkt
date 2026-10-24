#lang racket/base
(require racket/list net/url "oauth-uri-policy.rkt" "oauth-metadata.rkt" "protected-resource.rkt" "principal.rkt")
(provide authorization-metadata-urls discover-authorization discover-authorization-for-resource)
(define (non-root-path u)
  (if (equal? (url-path u) (list (path/param "" '()))) '() (url-path u)))
(define (well-known-url u name #:append? [append? #f])
  (define path (non-root-path u))
  (define prefix (list (path/param ".well-known" '()) (path/param name '())))
  (url->string
   (struct-copy url u [path
     (if append?
         (append (if (and (pair? path) (equal? (last path) (path/param "" '()))) (drop-right path 1) path) prefix)
         (append prefix path))])))
(define (authorization-metadata-urls issuer)
  (define u (identifier-url! issuer 'authorization-metadata-urls))
  (remove-duplicates
   (append (list (well-known-url u "oauth-authorization-server")
                 (well-known-url u "openid-configuration"))
           (if (null? (non-root-path u)) '()
               (list (well-known-url u "openid-configuration" #:append? #t))))))
;; #f is the fetch adapter's explicit unavailable-document outcome. Exceptions,
;; malformed documents, and identity mismatches never become permissive fallback.
(define (fetch-first urls fetch who)
  (or (for/or ([url (in-list urls)]) (fetch url))
      (error who "no metadata document available")))
(define (resource-document! document expected)
  (unless (hash? document) (error 'discover-authorization "resource metadata must be an object"))
  (define resource (hash-ref document 'resource #f))
  (https-uri! resource 'discover-authorization)
  (when (and expected (not (equal? resource expected)))
    (error 'discover-authorization "protected resource identifier mismatch"))
  (define issuers (hash-ref document 'authorization_servers '()))
  (unless (and (list? issuers) (pair? issuers))
    (error 'discover-authorization "resource has no authorization server"))
  (for ([issuer (in-list issuers)]) (identifier-url! issuer 'discover-authorization))
  (check-scopes! (hash-ref document 'scopes_supported '()))
  document)
(define (discover-from-resource document fetch expected select-issuer)
  (resource-document! document expected)
  (define issuers (hash-ref document 'authorization_servers))
  (define issuer (select-issuer issuers))
  (unless (member issuer issuers) (error 'discover-authorization "selected issuer was not advertised"))
  (define urls (authorization-metadata-urls issuer))
  (define metadata
    (or (for/or ([url (in-list urls)] [index (in-naturals)])
          (define value (fetch url))
          (and value (validate-authorization-metadata! value issuer #:oidc? (positive? index))))
        (error 'discover-authorization "no metadata document available")))
  (check-scopes! (hash-ref metadata 'scopes_supported '()))
  (values document metadata))
(define (discover-authorization resource-metadata-url fetch #:resource [expected #f] #:select-issuer [select-issuer car])
  (https-uri! resource-metadata-url 'discover-authorization)
  (when expected (https-uri! expected 'discover-authorization))
  (discover-from-resource (fetch-first (list resource-metadata-url) fetch 'discover-authorization)
                          fetch expected select-issuer))
(define (discover-authorization-for-resource resource fetch #:metadata-url [metadata-url #f]
                                             #:select-issuer [select-issuer car])
  (define u (string->url (https-uri! resource 'discover-authorization-for-resource)))
  (define urls
    (if metadata-url
        (list (https-uri! metadata-url 'discover-authorization-for-resource))
        (remove-duplicates
         (list (protected-resource-metadata-url resource)
               (url->string (struct-copy url u [query '()]
                              [path (list (path/param ".well-known" '())
                                          (path/param "oauth-protected-resource" '()))]))))))
  (discover-from-resource (fetch-first urls fetch 'discover-authorization-for-resource)
                          fetch resource select-issuer))
