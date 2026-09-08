#lang racket/base
(require rackunit mcp/schema mcp/interaction mcp/error
         "../mcp/private/elicitation-format.rkt" "../mcp/private/input-response.rkt")
(define (form name)
  (hasheq 'message "Enter a value" 'requestedSchema
          (hasheq 'type "object" 'properties (hasheq 'value (hasheq 'type "string" 'format name)))))
(define (answer value) (hasheq 'action "accept" 'content (hasheq 'value value)))
(define cases
  '(("uri" "file:///tmp/a" #t) ("uri" "x:" #t) ("uri" "x://" #t)
    ("uri" "x://:80" #t) ("uri" "x://user@" #t) ("uri" "x:///" #t)
    ("uri" "http://[:::]" #f) ("uri" "http://[1::::2]" #f)
    ("uri" "http://[1.2.3.4::]" #f) ("uri" "http://[1:2:3:4:5:6:7:8::]" #f)
    ("uri" "http://[1:2:3:4:5:6:7::]" #t) ("uri" "http://[1::2::3]" #f)
    ("uri" "x://[v1.a:b]/" #t) ("uri" "x://[v1.%20]/" #f)
    ("uri" "x://[fe80::1%25eth0]/" #f) ("uri" "x://u@v@host/" #f)
    ("uri" "x:/a?b/c?d#e/f?g" #t) ("uri" "x:/a#b#c" #f)
    ("uri" "x:/%00" #t) ("uri" "x:/\u0000" #f)
    ("date-time" "1999-01-01T00:59:60+01:00" #t)
    ("date-time" "1998-12-31T22:59:60-01:00" #t)
    ("date-time" "1998-12-30T23:59:60Z" #f)
    ("date-time" "1998-12-31T23:59:60+01:00" #f)
    ("date-time" "2000-02-29T23:59:59-00:00" #t)
    ("date" "0000-02-29" #t) ("date" "1900-02-29" #f)
    ("email" "\"a@b\"@example.test" #t) ("email" "a@[IPv6:1::2::3]" #f)
    ("email" "\"a\\\"b\"@example.test" #t) ("email" "\"a\\\"@example.test" #f)))
(for ([sample (in-list cases)])
  (define name (car sample)) (define value (cadr sample)) (define expected (caddr sample))
  (check-equal? (elicitation-format-valid? name value) expected (format "~s" sample))
  (if expected
      (check-not-exn (lambda () (validate-input-response (form name) (answer value))))
      (check-exn (lambda (e) (and (exn:fail:mcp? e) (= (exn:fail:mcp-code e) -32602)))
                 (lambda () (validate-input-response (form name) (answer value)))))
  ;; General schema validation keeps format as an annotation.
  (check-true (valid? (hash-ref (form name) 'requestedSchema) (hasheq 'value value))))
(for ([name '("date" "date-time" "email" "uri")])
  (check-not-exn (lambda () (validate-input-response (form name) (hasheq 'action "accept" 'content (hasheq)))))
  (for ([action '("decline" "cancel")])
    (check-not-exn (lambda () (validate-input-response (form name) (hasheq 'action action)))))
  (for ([value '(#f null 123)])
    (check-exn exn:fail:mcp? (lambda () (validate-input-response (form name) (answer value))))))

;; Callback output is checked before a new MRTR request or task update is sent.
(for* ([task? '(#f #t)] [valid? '(#f #t)])
  (define calls '())
  (define input (hasheq 'method "elicitation/create" 'params (form "date")))
  (define (request method params)
    (set! calls (append calls (list (cons method params))))
    (case (length calls)
      [(1) (if task? (hasheq 'resultType "task" 'taskId "owned")
               (hasheq 'resultType "input_required" 'requestState "opaque" 'inputRequests (hasheq 'date input)))]
      [(2) (if task? (hasheq 'status "input_required" 'inputRequests (hasheq 'date input))
               (hasheq 'resultType "complete"))]
      [else (hasheq 'resultType "complete" 'status "completed")]))
  (define (run)
    (run-interaction request "tools/call" (hasheq) #:wait void
      #:elicit (lambda (_) (answer (if valid? "2024-02-29" "2023-02-29")))
      #:navigate (lambda (_) (error 'test "unexpected navigation"))))
  (if valid? (check-not-exn run) (check-exn exn:fail:mcp? run))
  (check-equal? (map car calls)
                (if task?
                    (if valid? '("tools/call" "tasks/get" "tasks/update" "tasks/get") '("tools/call" "tasks/get"))
                    (if valid? '("tools/call" "tools/call") '("tools/call")))))
(for ([input (list (hasheq 'mode "url" 'message "Open" 'url "not a URI" 'elicitationId "x")
                   (hasheq 'mode "form" 'message "Bad" 'requestedSchema (hasheq 'type "array")))])
  (define callbacks 0) (define requests 0)
  (check-exn #rx"Invalid elicitation request"
    (lambda ()
      (run-interaction
       (lambda (_m _p) (set! requests (add1 requests))
         (hasheq 'resultType "input_required" 'inputRequests
                 (hasheq 'x (hasheq 'method "elicitation/create" 'params input))))
       "tools/call" (hasheq)
       #:elicit (lambda (_) (set! callbacks (add1 callbacks)))
       #:navigate (lambda (_) (set! callbacks (add1 callbacks))))))
  (check-equal? callbacks 0) (check-equal? requests 1))
