#lang racket/base
(require "../storage.rkt" "upstream-bridge-state.rkt")
(provide recover-upstream-request!)
(define (recover-upstream-request! bridge store snapshot handle #:principal principal #:credential-id credential
                                   #:action action #:outcome [outcome #f] #:capabilities [capabilities (hasheq)])
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'upstream "recovery must own its storage transaction boundaries"))
  (unless (memq action '(outcome retry abandon)) (error 'upstream "recovery action must be outcome, retry, or abandon"))
  (define normalized (and (eq? action 'outcome) (freeze bridge (normalize-outcome outcome))))
  (define result #f)
  (unless (call-with-instance-worker store handle
    (lambda ()
      (set! result
        (store-transaction store
          (lambda ()
            (define instance (owned store handle principal))
            (check-binding! bridge snapshot instance credential (stored-instance-arguments instance))
            (define state (stored-instance-state instance))
            (unless (member (hash-ref state 'status) '("in-flight" "received"))
              (error 'upstream "interaction is not awaiting recovery"))
            (record-event! store handle (hasheq 'kind "upstream-recovery" 'action (symbol->string action)))
            (case action
              [(outcome) (local-outcome (stored-instance-state (record-outcome! bridge store instance normalized)) capabilities)]
              [(abandon)
               (define final (hasheq 'error (hasheq 'code -32603 'message "Upstream interaction abandoned")))
               (save-state! bridge store instance (hash-set* state 'status "complete" 'outcome final))
               final]
              [(retry)
               (save-state! bridge store instance (hash-set state 'status "ready"))
               (hasheq 'result (hasheq 'resultType "input_required" 'inputRequests (hasheq)
                 'requestState (continuation-token! store handle (string->symbol (number->string (hash-ref state 'round))))))]))))))
    (error 'upstream "upstream request is active; recovery cannot race its execution"))
  result)
