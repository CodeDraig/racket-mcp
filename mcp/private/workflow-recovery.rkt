#lang racket/base
(require "../storage.rkt" "../json.rkt" "../schema.rkt" "../codec.rkt" "../descriptor.rkt" "../freshness.rkt" "workflow-changes.rkt")
(provide recover-workflow!)
(define (recover-workflow! store handle stage action #:outcome [outcome missing] #:principal principal #:codecs [codecs (hash)])
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'recover-workflow! "recovery must own its storage transaction boundaries"))
  (define result #f)
  (define keys '())
  (when (committed-result? outcome)
    (unless (eq? action 'outcome) (error 'recover-workflow! "commit acknowledgement requires an outcome repair"))
    (set! keys (committed-result-keys outcome))
    (set! outcome (committed-result-result outcome)))
  (unless (call-with-instance-worker store handle
    (lambda ()
      (define instance (or (load-instance store handle) (error 'recover-workflow! "unknown handle")))
      (unless (equal? principal (stored-instance-principal instance)) (error 'recover-workflow! "foreign handle"))
      (define state (stored-instance-state instance))
      (unless (equal? (hash-ref state 'status) "working") (error 'recover-workflow! "execution is not recoverable"))
      (define effects (hash-ref state 'effects))
      (define intent (hash-ref effects stage (lambda () (error 'recover-workflow! "no effect intent"))))
      (unless (= (hash-ref state 'position) (hash-ref intent 'position)) (error 'recover-workflow! "effect is not the current stage"))
      ;; Keep the instance claim while application encoding runs, but allow
      ;; unrelated requests to use SQLite. The final CAS detects stale snapshots.
      (when (and (eq? action 'outcome) (hash-ref intent 'codec #f))
        (define identity (hash-ref intent 'codec))
        (set! outcome (encode-value (lookup-codec codecs (hash-ref identity 'name) (hash-ref identity 'version)) outcome)))
      (define next
        (case action
          [(outcome) (when (or (missing? outcome) (not (valid? (hash-ref intent 'schema) outcome))) (error 'recover-workflow! "valid outcome required"))
                     (hash-set* state 'position (add1 (hash-ref state 'position)) 'values (hash-set (hash-ref state 'values) stage outcome))]
          [(retry) (hash-set state 'effects (hash-set effects stage (hash-set intent 'status "retry-authorized")))]
          [(abandon) (hash-set* state 'status "abandoned" 'result (error-result "Execution abandoned during recovery"))]
          [else (error 'recover-workflow! "unknown recovery action")]))
      (set! result
        (store-transaction store
          (lambda ()
            (when (eq? action 'outcome)
              (record-workflow-changes! store principal keys #:handle handle #:stage stage))
            (record-event! store handle (hasheq 'kind "recovery" 'stage (symbol->string stage) 'action (symbol->string action)))
            (update-instance! store instance next))))))
    (error 'recover-workflow! "execution is active; recovery cannot change an in-flight effect"))
  result)

