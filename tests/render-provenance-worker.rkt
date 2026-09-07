#lang racket/base
(require racket/file mcp)
(module+ main
  (define args (current-command-line-arguments))
  (define database (vector-ref args 0))
  (define marker (vector-ref args 1))
  (define state-file (vector-ref args 2))
  (resource (leaf) #:uri "docs:///leaf"
    (call-with-output-file marker (lambda (out) (displayln "read" out)) #:exists 'append)
    "Leaf")
  (workflow (job) #:version "1"
    (checkpoint [actual Any] (embed (leaf)))
    (checkpoint [literal Any] (string->json (json->string actual)))
    (await-input [gate Any] (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
    (structured-result (hasheq 'literal literal) #:content (list actual)))
  (define store (open-sqlite-store database))
  (define rt (make-runtime (make-interface #:tools (list job) #:resources (list leaf)) #:store store))
  (define params (hasheq 'name "job" '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq)))))
  (define resumed? (file-exists? state-file))
  (define result
    (dispatch rt "tools/call"
      (if resumed? (hash-set* params 'requestState (file->string state-file)
                             'inputResponses (hasheq 'gate (hasheq 'action "decline"))) params)))
  (unless resumed?
    (call-with-output-file state-file (lambda (out) (display (hash-ref result 'requestState) out))))
  (write-json result) (newline)
  (close-store! store)
  (custodian-shutdown-all (runtime-custodian rt)))
