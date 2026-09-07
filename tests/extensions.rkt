#lang racket/base
(require rackunit racket/port racket/runtime-path mcp
         (rename-in "../examples/extensions/approval.rkt" [request-approval ask])
         (for-syntax racket/base syntax/parse))
(workflow (approval [name String]) #:version "1"
  (ask answer (string-append "Approve " name "?"))
  (text-result (hash-ref answer 'action)))
(check-regexp-match #rx"approved" (workflow-descriptor-fingerprint (tool-descriptor-workflow approval)))
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list approval)) #:store store))
(define params (hasheq '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq)))
                       'name "approval" 'arguments (hasheq 'name "Ada")))
(define pending (dispatch rt "tools/call" params))
(check-equal? (hash-ref (hash-ref (hash-ref (hash-ref pending 'inputRequests) 'answer) 'params) 'message) "Approve Ada?")
(define done (dispatch rt "tools/call" (hash-set* params 'requestState (hash-ref pending 'requestState)
                                                'inputResponses (hasheq 'answer (hasheq 'action "decline")))))
(check-equal? (hash-ref done 'content) (list (text-content "decline")))
;; Expansion is lexical, so a host function with the same spelling is unaffected.
(check-equal? (let ([ask (lambda (x) (+ x 1))]) (ask 2)) 3)
(define-mcp-extension declare-echo #:declaration
  (syntax-parser [(_ name:id) #'(tool (name [text String]) (text-result text))]))
(declare-echo echo)
(check-equal? (dispatch (make-runtime (make-interface #:tools (list echo))) "tools/call"
                       (hasheq '_meta (request-meta) 'name "echo" 'arguments (hasheq 'text "ok")))
              (text-result "ok"))
;; Extension-generated invalid core forms are rejected by the workflow compiler.
(define-mcp-extension bad-checkpoint #:workflow
  (syntax-parser [(_ id:id) #'(checkpoint [id Integer] 1)]))
(check-exn exn:fail:syntax?
           (lambda () (expand #'(workflow (bad [x Integer]) #:version "1" (bad-checkpoint x) (text-result "bad")))))
(check-exn exn:fail:syntax? (lambda () (expand #'(let () (ask answer "No workflow")))))
(check-exn exn:fail:syntax?
           (lambda () (expand #'(workflow (hidden) #:version "1" (checkpoint [value Any] (ask answer "Hidden")) (text-result "bad")))))
(custodian-shutdown-all (runtime-custodian rt))
(close-store! store)

(define-runtime-path executable "extension-server.rkt")
(define-values (process output input errors)
  (subprocess #f #f #f (find-executable-path "racket") executable))
(write-json (hasheq 'jsonrpc "2.0" 'id 7 'method "tools/call"
                    'params (hasheq '_meta (request-meta) 'name "ping")) input)
(newline input) (flush-output input)
(check-not-false (sync/timeout 5 output))
(define reply (read-json output))
(check-equal? (hash-ref (hash-ref reply 'result) 'content) (list (text-content "pong")))
(close-output-port input)
(subprocess-wait process)
(check-equal? (subprocess-status process) 0 (port->string errors))
(close-input-port output) (close-input-port errors)
