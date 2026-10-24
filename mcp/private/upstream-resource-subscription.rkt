#lang racket/base
(require racket/list "../runtime.rkt" "../json.rkt" "upstream-resources.rkt" "upstream-subscription-state.rkt" "upstream-subscription-core.rkt"
         (submod "../runtime.rkt" upstream-task-subscriptions))
(provide call-with-upstream-resource-subscription)
(define (call-with-upstream-resource-subscription rt source snapshot request uris proc
          #:principal principal #:timeout [timeout 5] #:propagate-loss? [propagate? #t])
  (unless (boolean? propagate?)
    (raise-argument-error 'call-with-upstream-resource-subscription "boolean?" propagate?))
  (unless (runtime? rt) (raise-argument-error 'call-with-upstream-resource-subscription "runtime?" rt))
  (unless (and (procedure? request) (procedure-arity-includes? request 2))
    (raise-argument-error 'call-with-upstream-resource-subscription "request procedure accepting method and parameters" request))
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-upstream-resource-subscription "procedure accepting a subscription" proc))
  (unless (and (list? uris) (pair? uris) (andmap string? uris))
    (raise-argument-error 'call-with-upstream-resource-subscription "nonempty list of resource URI strings" uris))
  (unless (and (rational? timeout) (> timeout 0))
    (raise-argument-error 'call-with-upstream-resource-subscription "positive finite timeout" timeout))
  (define requested (remove-duplicates (map string->immutable-string uris)))
  (define pinned (string->json (json->string snapshot)))
  ;; Resolve every requested URI before contacting the peer. These keys retain
  ;; the installed source identity through local views and principal partitions.
  (define keys (for/hash ([uri (in-list requested)]) (values uri (upstream-resource-change-keys source uri))))
  (call-with-upstream-subscription pinned request requested proc timeout
    'resourceSubscriptions "notifications/resources/updated" 'uri
    (lambda (uri _) (runtime-report-change! rt principal (hash-ref keys uri)))
    upstream-resource-subscription values
    (lambda (accepted failed? fallback?)
      (when propagate?
        (runtime-upstream-subscription-ended! rt principal
          (append-map (lambda (uri) (hash-ref keys uri)) accepted) '() failed? fallback?)))))

