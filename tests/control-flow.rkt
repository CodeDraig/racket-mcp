#lang racket/base
(require rackunit racket/file racket/match syntax/macro-testing mcp)

(define evaluations '())
(define (record label value) (set! evaluations (append evaluations (list label))) value)
(define request (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
(workflow (nested [x Integer]) #:version "1"
  (let ([x (record 'x 20)] [y (record 'y x)])
    (if (record 'condition (= y 10))
        (begin (await-input [first Any] request) (record 'yes x))
        (record 'no y))
    (match (list x y)
      [(list a b)
       (checkpoint [sum Integer] (+ a b))
       (await-input [second Any] request)
       (record 'sum sum)]))
  (text-result (number->string x)))
(define path (make-temporary-file "mcp-control-~a.sqlite"))
(define store (open-sqlite-store path))
(define (runtime) (make-runtime (make-interface #:tools (list nested)) #:store store))
(define params (hasheq '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))) 'name "nested" 'arguments (hasheq 'x 10)))
(define first (dispatch (runtime) "tools/call" params))
(check-equal? evaluations '(x y condition))
(check-equal? (hash-keys (hash-ref first 'inputRequests)) '(let/then/first))
;; Close and reopen the database between branches: no saved lexical value may
;; depend on the old runtime, and earlier initializers must not run again.
(close-store! store)
(set! store (open-sqlite-store path))
(define retry (hash-set params 'requestState (hash-ref first 'requestState)))
(define second (dispatch (runtime) "tools/call"
                         (hash-set retry 'inputResponses (hasheq 'let/then/first (hasheq 'action "decline")))))
(check-equal? evaluations '(x y condition yes))
(check-equal? (hash-keys (hash-ref second 'inputRequests)) '(let/after/case0/second))
(define done (dispatch (runtime) "tools/call"
                       (hash-set* retry 'requestState (hash-ref second 'requestState)
                                  'inputResponses (hasheq 'let/after/case0/second (hasheq 'action "cancel")))))
(check-equal? (hash-ref done 'content) (list (text-content "10")))
(check-equal? evaluations '(x y condition yes sum))
(check-equal? (dispatch (runtime) "tools/call" retry) done)
(check-equal? evaluations '(x y condition yes sum))
(close-store! store)
(delete-file path)
(check-exn exn:fail:syntax?
           (lambda () (convert-compile-time-error
                       (workflow (bad) #:version "1" (let ([x 1] [x 2]) (text-result "bad"))))))
(check-exn exn:fail:syntax?
           (lambda () (convert-compile-time-error
                       (workflow (bad-hidden) #:version "1"
                         (text-result (begin (await-input [x Any] request) "bad"))))))
