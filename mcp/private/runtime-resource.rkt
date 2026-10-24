#lang racket/base
(require racket/list
         "runtime-state.rkt"
         "runtime-changes.rkt"
         "runtime-render.rkt"
         "../clock.rkt"
         "../descriptor.rkt"
         "../workflow.rkt"
         (submod "../workflow.rkt" private)
         "../freshness.rkt"
         "../authorization.rkt"
         "../presentation.rkt"
         "../json.rkt"
         "../error.rkt")
(provide dispatch-resource-read)
(struct resource-snapshot (result reads keys expires) #:transparent)
(define current-resource-snapshots (make-parameter #f))
(define (snapshot-with-ttl snapshot ttl)
  (struct-copy resource-snapshot snapshot [result (hash-set (resource-snapshot-result snapshot) 'ttlMs ttl)]))
(define (dispatch-resource-read rt params render-call run-domain-workflow)
  (define context (current-request-context))
  (define principal (request-context-principal context))
  (define caps (request-context-capabilities context))
  (define iface (runtime-interface rt))
  (define meta (hash-ref params '_meta))
  (define uri (hash-ref params 'uri #f))
  (unless (string? uri) (mcp-error -32602 "Resource URI must be a string"))
  (define matches (filter values (for/list ([d (in-list (interface-descriptor-resources iface))])
                                   (define args ((resource-descriptor-matcher d) uri)) (and args (cons d args)))))
  (unless (= (length matches) 1) (mcp-error -32602 "Unknown or ambiguous resource URI" (hasheq 'uri uri)))
  (define d (caar matches))
  (define args (bind-arguments (resource-descriptor-arguments d) (cdar matches)))
  (define renderer-version (renderer-fingerprint (resource-descriptor-renderer d)))
  (define program
    (and (resource-descriptor-workflow d)
         (workflow-add-fingerprint-suffix (resource-descriptor-workflow d)
                                          (string-append ":renderer:" renderer-version))))
  (define dependencies (change-keys! ((resource-descriptor-depends-on d) args)))
  (define parent (current-resource-snapshots))
  (define bypass? (or program (current-workflow-state) (current-workflow-invocation-key)
                      (hash-has-key? params 'inputResponses)))
  (define (compute)
    (define children (box '()))
    (define content
      (parameterize ([current-resource-snapshots children])
        (render-call
     (lambda ()
       (define value
         (if program
             (run-domain-workflow program args)
             (apply (resource-descriptor-handler d) (map (lambda (a) (hash-ref args (argument-name a))) (resource-descriptor-arguments d)))))
       (if (and (resource-descriptor-renderer d) (not (input-required? value)))
           (apply-resource-renderer (resource-descriptor-renderer d) value) value))
     (if program (workflow-executable-fingerprint program (current-workflow-adapters)) (string-append "render/1:renderer:" renderer-version)))))
    (define reads (remove-duplicates (cons uri (append-map resource-snapshot-reads (unbox children)))))
    (define keys (remove-duplicates (append dependencies (append-map resource-snapshot-keys (unbox children)))))
    (define now (cache-clock (runtime-cache rt)))
    (define expires
      (apply min (+ now (if bypass? 0 (resource-descriptor-ttl-ms d)))
             (if (verified-principal? principal)
                 (+ now (max 0 (* 1000 (- (verified-principal-expiry principal) (mcp-current-seconds))))) +inf.0)
             (map resource-snapshot-expires (unbox children))))
    (define limited-ttl (max 0 (inexact->exact (floor (- expires now)))))
    (resource-snapshot
      (if (input-required? content) content
          (hash-set (hash-set* (hasheq 'resultType "complete" 'contents
                                 (presentation-contents content uri (resource-descriptor-mime-type d))) 'ttlMs 0 'cacheScope "private") 'ttlMs limited-ttl))
      reads keys expires))
  (define snapshot
    (if bypass? (compute)
        (cache-ref! (runtime-cache rt)
                    (cache-partition (principal-key principal)
                      (list (runtime-cache-namespace rt) ((runtime-cache-context rt) principal) (json->string caps)
                            (json->string (for/hasheq ([(k v) (in-hash args)] #:unless (missing? v)) (values k v)))
                            (json->string dependencies)))
                    uri resource-snapshot-keys
                    (lambda (s) (hash-ref (resource-snapshot-result s) 'ttlMs 0)) compute
                    #:cacheable? (lambda (s) (equal? (hash-ref (resource-snapshot-result s) 'resultType #f) "complete"))
                    #:usable? (lambda (s) (andmap (lambda (child-uri)
                       ((runtime-authorize rt) principal "resources/read" (hasheq 'uri child-uri '_meta meta)))
                       (resource-snapshot-reads s)))
                    #:on-hit snapshot-with-ttl #:expires-at resource-snapshot-expires
                    #:on-invalidated (lambda (s) (struct-copy resource-snapshot s
                      [result (if (input-required? (resource-snapshot-result s)) (resource-snapshot-result s)
                                  (hash-set (resource-snapshot-result s) 'ttlMs 0))]
                      [expires (cache-clock (runtime-cache rt))])))))
  (when parent (set-box! parent (cons snapshot (unbox parent))))
  (resource-snapshot-result snapshot)
)
