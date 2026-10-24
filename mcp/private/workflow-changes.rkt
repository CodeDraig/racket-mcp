#lang racket/base
(require "../storage.rkt" "../json.rkt" "../freshness.rkt" "workflow-context.rkt" "failure.rkt")
(provide record-workflow-changes! publish-workflow-changes!)
(define (record-workflow-changes! store principal keys #:handle handle #:stage stage)
  (unless (and (list? keys) (json-value? keys)) (error 'workflow "change keys must be a JSON list"))
  (unless (null? keys)
    (define outbox (record-committed-change! store principal keys))
    (record-event! store handle (hasheq 'kind "changes-recorded" 'stage (symbol->string stage) 'outbox (stored-instance-handle outbox)))))
(define (publish-workflow-changes!)
  ;; Publication is a retryable outbox delivery, not part of the effect outcome.
  (with-handlers ([non-break-failure? (lambda (e) (fprintf (current-error-port) "MCP change publication deferred: ~a\n" (failure-message e)))])
    ((current-workflow-change-publisher))))
