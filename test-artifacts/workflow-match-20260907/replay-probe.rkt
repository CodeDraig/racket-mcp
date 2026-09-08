#lang racket/base
(require rackunit racket/match mcp)
(define calls 0)
(define (extract value) (set! calls (add1 calls)) value)
(workflow (match-once [value String]) #:version "1"
  (match value
    [(app extract captured)
     (checkpoint [saved String] captured)
     (await-input [answer Any] (hasheq 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
     (text-result saved)]))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list match-once)) #:store store))
(define params (hasheq '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))) 'name "match-once" 'arguments (hasheq 'value "retained")))
(dynamic-wind void
 (lambda ()
  (define first (dispatch rt "tools/call" params))
  (check-equal? calls 1 "Match expression should run once before suspension")
  (define input (car (hash-keys (hash-ref first 'inputRequests))))
  (define result (dispatch rt "tools/call" (hash-set* params 'requestState (hash-ref first 'requestState) 'inputResponses (hasheq input (hasheq 'action "decline")))))
  (check-equal? result (text-result "retained"))
  (check-equal? calls 1 "Completed match work must not replay after input"))
 (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
