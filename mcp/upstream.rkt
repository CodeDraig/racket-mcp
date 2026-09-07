#lang racket/base
(require racket/list racket/string "descriptor.rkt" "schema.rkt" "json.rkt" "error.rkt")
(provide capture-snapshot make-upstream-interface check-upstream-compatibility!)
(define methods '("server/discover" "tools/list" "resources/list" "resources/templates/list" "prompts/list"))
(define (result! outcome)
  (when (hash-has-key? outcome 'error) (mcp-error -32603 "Upstream request failed" (hash-ref outcome 'error)))
  (hash-ref outcome 'result outcome))
(define (capture-snapshot request)
  (define discovery (result! (request "server/discover" (hasheq))))
  (define capabilities (hash-ref discovery 'capabilities (hasheq)))
  (for/hasheq ([method (in-list methods)])
    (define key (case (string->symbol method) [(tools/list) 'tools] [(resources/list) 'resources] [(resources/templates/list) 'resourceTemplates] [(prompts/list) 'prompts] [else #f]))
    (define capability (case (string->symbol method) [(tools/list) 'tools] [(prompts/list) 'prompts] [else 'resources]))
    (define result (cond [(not key) discovery]
                         [(hash-has-key? capabilities capability) (result! (request method (hasheq)))]
                         [else (hasheq 'resultType "complete" key '() 'ttlMs 0 'cacheScope "private")]))
    (define all
      (if (not key) result
          (let loop ([page result] [items '()] [seen '()])
            (define combined (append items (hash-ref page key)))
            (define next (hash-ref page 'nextCursor #f))
            (cond [(not next) (hash-set (hash-remove result 'nextCursor) key combined)]
                  [(member next seen) (error 'capture-snapshot "upstream repeated a pagination cursor")]
                  [else (loop (result! (request method (hasheq 'cursor next))) combined (cons next seen))]))))
    (values (string->symbol method) all)))
(define (check-upstream-compatibility! snapshot request)
  (define fresh (capture-snapshot request))
  (for ([method '(tools/list prompts/list resources/list resources/templates/list)])
    (define field (case method [(tools/list) 'tools] [(prompts/list) 'prompts] [(resources/list) 'resources] [else 'resourceTemplates]))
    (unless (equal? (hash-ref (hash-ref snapshot method) field) (hash-ref (hash-ref fresh method) field))
      (error 'upstream "pinned interface changed; refresh and review the snapshot"))) #t)
(define (make-upstream-interface snapshot request)
  (define verified? #f) (define lock (make-semaphore 1))
  (define (invoke method params)
    (call-with-semaphore lock (lambda () (unless verified? (check-upstream-compatibility! snapshot request) (set! verified? #t))))
    (define result (result! (request method params)))
    (unless (equal? (hash-ref result 'resultType #f) "complete")
      (mcp-error -32603 "Upstream MRTR/Tasks requires a durable handle-translation adapter, which is not yet implemented")) result)
  (make-interface
    #:tools
    (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'tools/list) 'tools))])
      (define schema (hash-ref wire 'inputSchema)) (check-schema! schema)
      (make-tool (hash-ref wire 'name) '()
                 (lambda (bound) (invoke "tools/call" (hasheq 'name (hash-ref wire 'name) 'arguments bound)))
                 #:description (hash-ref wire 'description "") #:output (hash-ref wire 'outputSchema #f)
                 #:input-schema schema #:raw? #t))))
