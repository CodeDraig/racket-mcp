#lang racket/base
(require "json.rkt")
(provide run-interaction)
;; request is supplied by the caller and must issue a fresh JSON-RPC ID each time.
;; No request is retried after an exception or uncertain initial response.
(define (run-interaction request method params #:elicit elicit #:navigate navigate
                         #:max-rounds [max-rounds 100] #:wait [wait (lambda (ms) (sync (alarm-evt (+ (current-inexact-milliseconds) ms))))])
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
           (case (string->symbol (hash-ref result 'resultType))
             [(input_required)
              (loop method (hash-set* params 'requestState (hash-ref result 'requestState) 'inputResponses (answers (hash-ref result 'inputRequests))) (sub1 remaining))]
             [(task) (wait (hash-ref result 'pollIntervalMs 100)) (loop "tasks/get" (hasheq 'taskId (hash-ref result 'taskId)) (sub1 remaining))]
             [else
              (if (not (equal? method "tasks/get")) outcome
                  (case (string->symbol (hash-ref result 'status))
                    [(working) (wait (hash-ref result 'pollIntervalMs 100)) (loop method params (sub1 remaining))]
                    [(input_required)
                     (define update (request "tasks/update" (hash-set params 'inputResponses (answers (hash-ref result 'inputRequests)))))
                     (if (hash-has-key? update 'error) update (loop method params (sub1 remaining)))]
                    [else outcome]))])])) )
