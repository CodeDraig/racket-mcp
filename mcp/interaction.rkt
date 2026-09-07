#lang racket/base
(require "json.rkt")
(provide run-interaction)
;; request is supplied by the caller and must issue a fresh JSON-RPC ID each time.
;; No request is retried after an exception or uncertain initial response.
(define (run-interaction request method params #:elicit elicit #:navigate navigate
                         #:max-rounds [max-rounds 100] #:wait [wait (lambda (ms) (sync (alarm-evt (+ (current-inexact-milliseconds) ms))))])
  (unless (exact-positive-integer? max-rounds)
    (raise-argument-error 'run-interaction "exact-positive-integer?" max-rounds))
  (let loop ([method method] [params params] [remaining max-rounds])
    (when (zero? remaining) (error 'run-interaction "interaction round limit exceeded"))
    (define outcome (request method params))
    (cond [(hash-has-key? outcome 'error) outcome]
          [else
           (define result (hash-ref outcome 'result outcome))
           (define (answers requests)
             (for/hasheq ([(id request) (in-hash requests)])
               (unless (equal? (hash-ref request 'method) "elicitation/create") (error 'run-interaction "unsupported input method"))
               (define input (hash-ref request 'params))
               (values id ((if (equal? (hash-ref input 'mode "form") "url") navigate elicit) input))))
           (case (string->symbol (hash-ref result 'resultType "complete"))
             [(input_required)
              (unless (and (or (hash-has-key? result 'requestState) (hash-has-key? result 'inputRequests))
                           (or (not (hash-has-key? result 'requestState)) (string? (hash-ref result 'requestState)))
                           (or (not (hash-has-key? result 'inputRequests)) (hash? (hash-ref result 'inputRequests))))
                (error 'run-interaction "Malformed input_required result; refusing automatic retry"))
              (define retry (hash-remove (hash-remove params 'requestState) 'inputResponses))
              (define with-state (if (hash-has-key? result 'requestState)
                                     (hash-set retry 'requestState (hash-ref result 'requestState)) retry))
              (define with-input (if (hash-has-key? result 'inputRequests)
                                     (hash-set with-state 'inputResponses (answers (hash-ref result 'inputRequests))) with-state))
              (loop method with-input (sub1 remaining))]
             [(task) (wait (hash-ref result 'pollIntervalMs 100)) (loop "tasks/get" (hasheq 'taskId (hash-ref result 'taskId)) (sub1 remaining))]
             [else
              (if (not (equal? method "tasks/get")) outcome
                  (case (string->symbol (hash-ref result 'status))
                    [(working) (wait (hash-ref result 'pollIntervalMs 100)) (loop method params (sub1 remaining))]
                    [(input_required)
                     (define update (request "tasks/update" (hash-set params 'inputResponses (answers (hash-ref result 'inputRequests)))))
                     (if (hash-has-key? update 'error) update (loop method params (sub1 remaining)))]
                    [else outcome]))])])) )
