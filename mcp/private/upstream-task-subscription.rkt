#lang racket/base
(require racket/list "../runtime.rkt" "../json.rkt" "upstream-subscription-state.rkt" "upstream-subscription-core.rkt"
         (submod "../runtime.rkt" upstream-task-subscriptions))
(provide call-with-upstream-task-subscription)
(define (call-with-upstream-task-subscription rt snapshot request ids proc
          #:principal principal #:capabilities capabilities #:timeout [timeout 5]
          #:propagate-loss? [propagate? #t])
  (unless (boolean? propagate?)
    (raise-argument-error 'call-with-upstream-task-subscription "boolean?" propagate?))
  (unless (runtime? rt) (raise-argument-error 'call-with-upstream-task-subscription "runtime?" rt))
  (unless (and (list? ids) (pair? ids) (andmap string? ids))
    (raise-argument-error 'call-with-upstream-task-subscription "nonempty list of local task ID strings" ids))
  (unless (and (procedure? request) (procedure-arity-includes? request 2)
               (procedure? proc) (procedure-arity-includes? proc 1))
    (error 'call-with-upstream-task-subscription "expected request and consumer procedures"))
  (unless (and (rational? timeout) (> timeout 0))
    (raise-argument-error 'call-with-upstream-task-subscription "positive finite timeout" timeout))
  (define pinned (string->json (json->string snapshot)))
  (define caps (string->json (json->string capabilities)))
  (define local-ids (remove-duplicates (map string->immutable-string ids)))
  ;; Authorization and persisted snapshot/credential ownership precede all I/O.
  (define mapping
    (for/fold ([mapping (hash)]) ([id (in-list local-ids)])
      (define remote (hash-ref (runtime-upstream-task-target rt id pinned principal caps) 'remoteId))
      (hash-update mapping remote (lambda (prior) (append prior (list id))) '())))
  (call-with-upstream-subscription pinned request (hash-keys mapping) proc timeout
    'taskIds "notifications/tasks" 'taskId
    (lambda (remote detail)
      (for ([id (in-list (hash-ref mapping remote))])
        (runtime-observe-upstream-task! rt id detail #:principal principal #:capabilities caps)))
    upstream-task-subscription
    (lambda (accepted) (filter (lambda (id)
      (for/or ([remote (in-list accepted)]) (member id (hash-ref mapping remote)))) local-ids))
    (lambda (accepted failed? fallback?)
      (when propagate? (runtime-upstream-subscription-ended! rt principal '() accepted failed? fallback?)))))

