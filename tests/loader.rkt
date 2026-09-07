#lang racket/base
(require rackunit racket/file racket/string mcp mcp/scenario)
(define directory (make-temporary-file "mcp-loader-~a" 'directory))
(define application (build-path directory "application.rkt"))
(define helper (build-path directory "helper.rkt"))
(define instantiated (build-path directory "instantiated.txt"))
(dynamic-wind void
  (lambda ()
    (call-with-output-file helper
      (lambda (out) (display "#lang racket/base\n(provide helper)\n(define (helper) \"hello\")\n" out)))
    (call-with-output-file application
      (lambda (out)
        (display "#lang mcp\n(require \"helper.rkt\")\n(server #:name \"loaded\" #:version \"1\")\n" out)
        (fprintf out "(call-with-output-file ~s (lambda (out) (displayln \"instantiated\" out)))\n"
                 (path->string instantiated))
        (display
          "(define input (hasheq 'mode \"form\" 'message \"Continue?\" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
           (tool (identify) (structured-result (hasheq 'greeting (helper) 'principal (request-context-principal (current-request-context)) 'time (mcp-current-seconds))))
           (workflow (work) #:version \"1\" (await-input [answer Any] input) (text-result (helper)))
           (resource (report [name String]) #:uri \"report:///{name}\" #:workflow \"1\"
             (await-input [answer Any] input) (string-append (helper) name))
           (prompt (conversation [name String]) #:workflow \"1\"
             (await-input [answer Any] input) (role \"user\" (text-content (string-append (helper) name))))\n" out)))
    (check-exn exn:fail:contract? (lambda () (load-interface application #:runtime-build-id "")))
    (check-false (file-exists? instantiated))
    (define interface (load-interface application #:runtime-build-id "explicit-test-sdk-and-runtime/1"))
    (check-true (interface-descriptor? interface))
    (check-true (andmap tool-descriptor? (interface-descriptor-tools interface)))
    (check-equal? (file->string instantiated) "instantiated\n")
    (for ([transport '(local stdio http http)] [sse? '(#f #f #f #t)])
      (call-with-scenario-session interface
        (lambda (session)
          (define result (scenario-call session "tools/call" (hasheq 'name "identify")))
          (check-equal? (hash-ref (hash-ref result 'result) 'structuredContent)
                        (hasheq 'greeting "hello" 'principal "alice" 'time 7))
          (define (interact method params)
            (hash-ref (scenario-interact session method params
                        #:elicit (lambda (_) (hasheq 'action "accept" 'content (hasheq 'ok #t)))
                        #:navigate (lambda (_) (error 'test "unexpected navigation"))) 'result))
          (define tool-result (interact "tools/call" (hasheq 'name "work")))
          (check-equal? (hash-ref (car (hash-ref tool-result 'content)) 'text) "hello")
          (define resource-result (interact "resources/read" (hasheq 'uri "report:///Ada")))
          (check-equal? (hash-ref (car (hash-ref resource-result 'contents)) 'text) "helloAda")
          (define prompt-result (interact "prompts/get" (hasheq 'name "conversation" 'arguments (hasheq 'name "Ada"))))
          (check-equal? (hash-ref (hash-ref (car (hash-ref prompt-result 'messages)) 'content) 'text) "helloAda"))
        #:transport transport #:sse? sse? #:principal "alice" #:clock (make-manual-clock #:seconds 7)
        #:capabilities (hasheq 'elicitation (hasheq))))
    (check-equal? (file->string instantiated) "instantiated\n")
    (define fragment (build-path directory "fragment.rkt"))
    (call-with-output-file fragment
      (lambda (out) (display "#lang mcp\n(tool (simple) (text-result \"fragment\"))\n" out)))
    (check-false (interface-descriptor-server (load-interface fragment #:runtime-build-id "explicit-test-sdk-and-runtime/1")))
    (define invalid (build-path directory "invalid.rkt"))
    (call-with-output-file invalid
      (lambda (out) (display "#lang racket/base\n(provide mcp-interface)\n(define mcp-interface 42)\n" out)))
    (check-exn #rx"interface descriptor"
      (lambda () (load-interface invalid #:runtime-build-id "explicit-test-sdk-and-runtime/1"))))
  (lambda () (delete-directory/files directory)))
