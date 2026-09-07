#lang racket/base
(require rackunit racket/match mcp)
(define decisions 0)
(workflow (choose [n Integer]) #:version "1"
  (if (begin (set! decisions (add1 decisions)) (> n 0))
      (begin
        (await-input [response Any] (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
        (text-result "positive"))
      (text-result "nonpositive")))
(workflow (classify [items (array-schema Integer)]) #:version "1"
  (match items
    [(list x y)
     (checkpoint [sum Integer] (+ x y))
     (text-result (number->string sum))]
    [_ (text-result "other")]))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list choose classify)) #:store store))
(define meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))))
(define p (hasheq '_meta meta 'name "choose" 'arguments (hasheq 'n 1)))
(define initial (dispatch rt "tools/call" p))
(check-equal? decisions 1)
(define done (dispatch rt "tools/call" (hash-set* p 'requestState (hash-ref initial 'requestState) 'inputResponses (hasheq 'then/response (hasheq 'action "decline")))))
(check-equal? (hash-ref done 'content) (list (text-content "positive")))
(check-equal? decisions 1)
(check-equal? (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "classify" 'arguments (hasheq 'items '(2 3)))) 'content) (list (text-content "5")))
(check-equal? (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "classify" 'arguments (hasheq 'items '(2)))) 'content) (list (text-content "other")))
(close-store! store)
