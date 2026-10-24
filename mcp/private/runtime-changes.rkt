#lang racket/base
(require racket/list
         "runtime-state.rkt"
         "request-meta.rkt"
         "../clock.rkt"
         "../json.rkt"
         "../descriptor.rkt"
         "../freshness.rkt"
         "../subscription.rkt"
         "../authorization.rkt"
         "../external-changes.rkt")
(provide change-keys! runtime-report-change! runtime-upstream-subscription-ended! runtime-drain-changes! runtime-reconcile-changes!)
(define (change-keys! keys)
  (unless (and (list? keys) (json-value? keys)) (error 'freshness "dependency keys must be a JSON list"))
  keys)
(define (resource-notification-authorized? rt principal uri)
  (and (or (not (verified-principal? principal)) (> (verified-principal-expiry principal) (mcp-current-seconds)))
       ((runtime-authorize rt) principal "resources/read" (hasheq 'uri uri '_meta (request-meta)))))
(define (affected-resource-uris rt owner keys cached authorized?)
    (for/list ([target (in-list (subscription-resource-targets (runtime-subscriptions rt)))]
               #:when (equal? owner (principal-key (car target)))
               #:do [(define uri (cdr target))
                     (define reader (car target))
                     (define params (hasheq 'uri uri '_meta (request-meta))) ]
               #:when (authorized? reader uri)
               #:when
               (or (member uri cached)
                   (for/or ([d (in-list (interface-descriptor-resources (runtime-interface rt)))])
                     (define args ((resource-descriptor-matcher d) uri))
                     (and args
                          (parameterize ([current-interface (runtime-interface rt)]
                                         [current-request-context (request-context reader (hasheq) #f (lambda () #f) void)])
                            (define dependencies
                              (change-keys! ((resource-descriptor-depends-on d) (bind-arguments (resource-descriptor-arguments d) args))))
                            (ormap (lambda (key) (member key keys)) dependencies))))))
      uri))
(define/clock (runtime-report-change! rt principal keys)
  (change-keys! keys)
  (define owner (principal-key principal))
  ;; Invalidation precedes publication, including changes arriving externally.
  (define cached (invalidate-keys! (runtime-cache rt) keys #:principal owner))
  (define affected (affected-resource-uris rt owner keys cached
                     (lambda (reader uri) (resource-notification-authorized? rt reader uri))))
  (for ([uri (in-list (remove-duplicates affected))])
    (publish-change! (runtime-subscriptions rt) "notifications/resources/updated" (hasheq 'uri uri)
                     #:principal principal #:principal-key principal-key
                     #:authorized? (lambda (reader) (resource-notification-authorized? rt reader uri))))
  (remove-duplicates (append cached affected)))
(define/clock (runtime-upstream-subscription-ended! rt principal keys ids failed? fallback?)
  (change-keys! keys)
  (define owner (principal-key principal))
  ;; A missing feed makes cached reads uncertain; it is not a committed mutation
  ;; and must not fabricate resources/updated or task-state notifications.
  (define cached (if (null? keys) '() (invalidate-keys! (runtime-cache rt) keys #:principal owner)))
  (define affected
    (if (null? keys) '()
        (if fallback? #f
        (with-handlers ([(lambda (_) #t) (lambda (_) #f)])
          (affected-resource-uris rt owner keys cached (lambda (_reader _uri) #t))))))
  (close-subscriptions! (runtime-subscriptions rt)
    #:matches? (lambda (reader filter)
      (and (equal? owner (principal-key reader))
           (or (ormap (lambda (id) (member id ids)) (hash-ref filter 'taskIds '()))
               (if affected
                   (ormap (lambda (uri) (member uri affected)) (hash-ref filter 'resourceSubscriptions '()))
                   ;; Failed dependency calculation cannot justify retaining a
                   ;; resource listener for this principal with unknown coverage.
                   (pair? (hash-ref filter 'resourceSubscriptions '()))))))
    #:error-message (and failed? "Upstream subscription lost; re-listen and refresh cached data")))
(define/clock (runtime-drain-changes! rt)
  (unless (runtime-store rt) (error 'freshness "outbox storage is not configured"))
  (drain-change-outbox! (runtime-store rt)
                       (lambda (_id principal keys) (runtime-report-change! rt principal keys))))
(define/clock (runtime-reconcile-changes! rt source #:max-events [event-limit 1000] #:max-bytes [byte-limit 1048576])
  (unless (runtime-store rt) (error 'runtime-reconcile-changes! "a configured state store is required"))
  (define result (reconcile-external-changes! (runtime-store rt) source #:max-events event-limit #:max-bytes byte-limit))
  (runtime-drain-changes! rt)
  result)
