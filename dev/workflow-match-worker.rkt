#lang racket/base
(require racket/match mcp)
(define phase (make-parameter #f))
(define counter-path (make-parameter #f))
(define (observe value)
  (when (equal? (phase) "resume") (error 'test "matcher replayed in resumed process"))
  (call-with-output-file (counter-path) #:exists 'append (lambda (out) (displayln "matched" out)))
  (string-append "captured:" value))
(workflow (process-match [value String]) #:version "1"
  (match value
    [(app observe captured)
     (await-input [answer Any] (hasheq 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
     (text-result captured)]))
(module+ main
  (match-define (vector mode state-file continuation-file counter-file) (current-command-line-arguments))
  (define store (open-sqlite-store state-file))
  (define rt (make-runtime (make-interface #:tools (list process-match)) #:store store))
  (define params (hasheq '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq)))
                         'name "process-match" 'arguments (hasheq 'value "value")))
  (dynamic-wind void
    (lambda ()
      (parameterize ([phase mode] [counter-path counter-file])
        (cond [(equal? mode "start")
               (define pending (dispatch rt "tools/call" params))
               (call-with-output-file continuation-file #:exists 'truncate
                 (lambda (out) (write-json pending out)))]
              [else
               (define pending (call-with-input-file continuation-file read-json))
               (define input (car (hash-keys (hash-ref pending 'inputRequests))))
               (define result (dispatch rt "tools/call"
                 (hash-set* params 'requestState (hash-ref pending 'requestState)
                            'inputResponses (hasheq input (hasheq 'action "decline")))))
               (unless (equal? result (text-result "captured:value"))
                 (error 'test "unexpected resumed result: ~s" result))])))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
