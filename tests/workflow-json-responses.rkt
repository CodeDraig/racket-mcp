#lang racket/base
(require rackunit racket/file mcp mcp/rendering)

(define question
  (hasheq 'mode "form" 'message "Enter a number"
          'requestedSchema (object-schema (hasheq 'n Number))))
(define (answer n) (hash 'action "accept" 'content (hash 'n n)))
(define computations 0)
(workflow (single) #:version "1"
  (checkpoint [before Integer] (begin (set! computations (add1 computations)) 1))
  (await-input [value Any] question)
  (structured-result value))
(workflow (grouped) #:version "1"
  (checkpoint [before Integer] (begin (set! computations (add1 computations)) 1))
  (await-input ([first Any question] [second Any question]))
  (structured-result (hasheq 'first first 'second second)))
(resource (number-child) #:uri "responses:///number" #:workflow "1"
  (checkpoint [before Integer] (begin (set! computations (add1 computations)) 1))
  (await-input [value Any] question)
  (number->string (hash-ref (hash-ref value 'content) 'n)))
(tool (embedded)
  (hasheq 'resultType "complete" 'content (list (embed (number-child)))))

(define (with-store proc)
  (define path (make-temporary-file "mcp-json-responses-~a.sqlite"))
  (define store (open-sqlite-store path))
  (define rt #f)
  (define (runtime!)
    (set! rt (make-runtime (make-interface #:tools (list single grouped embedded) #:resources (list number-child)) #:store store)))
  (define (reopen!)
    (custodian-shutdown-all (runtime-custodian rt))
    (close-store! store)
    (set! store (open-sqlite-store path))
    (runtime!))
  (runtime!)
  (dynamic-wind void
    (lambda ()
      (proc (lambda (name token responses)
              (dispatch rt "tools/call"
                (hash-set* (hasheq 'name name '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))))
                           'requestState token 'inputResponses responses)))
            (lambda (name)
              (dispatch rt "tools/call"
                (hasheq 'name name '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))))))
            reopen!))
    (lambda ()
      (custodian-shutdown-all (runtime-custodian rt))
      (close-store! store)
      (delete-file path))))

(test-case "native numeric answers retain their identity through save, restart and replay"
  (set! computations 0)
  (with-store
    (lambda (resume start reopen!)
      (define token (hash-ref (start "single") 'requestState))
      (reopen!)
      (check-exn exn:fail:mcp? (lambda () (resume "single" token (hasheq 'value (answer "invalid")))))
      (define responses (hasheq 'value (answer 0.5) 'unknown (lambda () 'ignored)))
      (define done (resume "single" token responses))
      (check-equal? (hash-ref done 'structuredContent) (hasheq 'action "accept" 'content (hasheq 'n 1/2)))
      (reopen!)
      (check-equal? (resume "single" token responses) done)
      (check-equal? (resume "single" token (hasheq 'value (answer 1/2))) done)
      (check-exn exn:fail:mcp? (lambda () (resume "single" token (hasheq 'value (answer 0.75)))))
      (check-equal? computations 1))))

(test-case "partial native numeric input groups accept identical retries after restart"
  (set! computations 0)
  (with-store
    (lambda (resume start reopen!)
      (define token (hash-ref (start "grouped") 'requestState))
      (define partial (resume "grouped" token (hasheq 'first (answer 0.5))))
      (check-equal? (hash-keys (hash-ref partial 'inputRequests)) '(second))
      (reopen!)
      (check-equal? (resume "grouped" token (hasheq 'first (answer 0.5))) partial)
      (check-exn exn:fail:mcp? (lambda () (resume "grouped" token (hasheq 'first (answer 0.75)))))
      (define responses (hasheq 'first (answer 0.5) 'second (answer 0.75)))
      (define done (resume "grouped" token responses))
      (check-equal? (hash-ref done 'structuredContent)
                    (hasheq 'first (hasheq 'action "accept" 'content (hasheq 'n 1/2))
                            'second (hasheq 'action "accept" 'content (hasheq 'n 3/4))))
      (reopen!)
      (check-equal? (resume "grouped" token responses) done)
      (check-equal? computations 1))))

(test-case "native answers resume an embedded workflow and its parent after restart"
  (set! computations 0)
  (with-store
    (lambda (resume start reopen!)
      (define token (hash-ref (start "embedded") 'requestState))
      (reopen!)
      (define responses (hasheq 'e0/r0/value (answer 0.5)))
      (define done (resume "embedded" token responses))
      (check-equal? (hash-ref done 'content)
                    (list (hasheq 'type "resource" 'resource
                                  (hasheq 'uri "responses:///number" 'mimeType "text/plain" 'text "1/2"))))
      (reopen!)
      (check-equal? (resume "embedded" token responses) done)
      (check-exn exn:fail:mcp? (lambda () (resume "embedded" token (hasheq 'e0/r0/value (answer 0.75)))))
      (check-equal? computations 1))))

;; Exercise the renderer's independent history check without a child workflow
;; normalizing the response on its behalf.
(test-case "rendering history canonicalizes native answers independently"
  (define path (make-temporary-file "mcp-render-responses-~a.sqlite"))
  (define store (open-sqlite-store path))
  (define resolutions 0)
  (define layout (parameterize ([current-render-capture (box 0)]) (deferred-embedding "test:///child")))
  (define (resolve uri state responses key)
    (set! resolutions (add1 resolutions))
    (if state
        (begin
          (check-equal? (hash-ref (hash-ref responses 'value) 'action) "accept")
          (check = (hash-ref (hash-ref (hash-ref responses 'value) 'content) 'n) 1/2)
          (hasheq 'resultType "complete" 'contents (list (hasheq 'uri uri 'text "done"))))
        (hasheq 'resultType "input_required" 'requestState "child-state"
                'inputRequests (hasheq 'value (hasheq 'method "elicitation/create" 'params question)))))
  (define (render token responses)
    (render-layout store layout #:operation "test" #:arguments (hasheq) #:principal "alice"
                   #:fingerprint "1" #:resolve resolve #:state token #:responses responses))
  (dynamic-wind void
    (lambda ()
      (define token (hash-ref (render #f (hasheq)) 'requestState))
      (define responses (hasheq 'e0/r0/value (answer 0.5) 'ignored (lambda () 'ignored)))
      (define done (render token responses))
      (check-equal? done (hasheq 'type "resource" 'resource (hasheq 'uri "test:///child" 'text "done")))
      (close-store! store)
      (set! store (open-sqlite-store path))
      (check-equal? (render token responses) done)
      (check-exn exn:fail:mcp? (lambda () (render token (hasheq 'e0/r0/value (answer 0.75)))))
      (check-equal? resolutions 2))
    (lambda () (close-store! store) (delete-file path))))
