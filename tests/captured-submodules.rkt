#lang racket/base
(require rackunit racket/file racket/string compiler/cm mcp mcp/scenario mcp/private/module-observation)
(define directory (make-temporary-file "mcp-captured-submodules-~a" 'directory))
(define helper (build-path directory "helper.rkt"))
(define application (build-path directory "application.rkt"))
(dynamic-wind void
  (lambda ()
    (display-to-file
      "#lang racket/base\n(module early racket/base (provide greeting) (define (greeting) \"early\") (module nested racket/base (provide greeting) (define (greeting) \"nested\")))\n(module* late #f (provide greeting) (define (greeting) \"late\"))\n"
      helper)
    (display-to-file
      "#lang mcp\n(require (prefix-in a: (submod \"helper.rkt\" early)) (prefix-in b: (submod \"helper.rkt\" early nested)) (prefix-in c: (submod \"helper.rkt\" late)))\n(tool (greet) (text-result (string-append (a:greeting) \"/\" (b:greeting) \"/\" (c:greeting))))\n"
      application)
    (display-to-file
      "(workflow (work) #:version \"1\" (await-input [answer Any] (hasheq 'mode \"form\" 'message \"Continue?\" 'requestedSchema (object-schema (hasheq 'ok Boolean)))) (text-result (b:greeting)))\n"
      application #:exists 'append)
    (test-case "captured loader accepts actual nested application code"
      (define interface (load-interface application #:runtime-build-id "submodule-test-runtime"))
      (call-with-scenario-session interface
        (lambda (session)
          (define result (hash-ref (scenario-call session "tools/call" (hasheq 'name "greet")) 'result))
          (check-equal? (hash-ref (car (hash-ref result 'content)) 'text) "early/nested/late"))))
    (test-case "nested helper edits reject pending work but retained code remains valid"
      (define (program)
        (tool-descriptor-workflow
          (findf (lambda (tool) (equal? (tool-descriptor-name tool) "work"))
            (interface-descriptor-tools
              (load-interface application #:runtime-build-id "submodule-test-runtime")))))
      (define old (program))
      (define store (open-memory-store))
      (dynamic-wind void
        (lambda ()
          (define (start program) (run-workflow program store (hasheq) #:principal "alice"))
          (define (resume program result)
            (run-workflow program store (hasheq) #:principal "alice"
              #:state (hash-ref result 'requestState)
              #:responses (hasheq 'answer (hasheq 'action "decline"))))
          (define pending (start old))
          (display-to-file (string-replace (file->string helper) "\"nested\"" "\"updated\"") helper #:exists 'truncate)
          (module-cache-clear!)
          (define changed (program))
          (check-exn exn:fail:recovery? (lambda () (resume changed pending)))
          (check-equal? (hash-ref (car (hash-ref (resume old pending) 'content)) 'text) "nested")
          (check-equal? (hash-ref (car (hash-ref (resume changed (start changed)) 'content)) 'text) "updated"))
        (lambda () (close-store! store))))
    (test-case "compiled application imports separately loaded submodule code"
      (managed-compile-zo application)
      (module-cache-clear!)
      (define interface (load-interface application #:runtime-build-id "submodule-test-runtime"))
      (call-with-scenario-session interface
        (lambda (session)
          (define result (hash-ref (scenario-call session "tools/call" (hasheq 'name "greet")) 'result))
          (check-equal? (hash-ref (car (hash-ref result 'content)) 'text) "early/updated/late"))))
    (for ([compiled? '(#f #t)])
     (test-case (format "observation resolves nested submodules, compiled: ~a" compiled?)
      (define observed-file (build-path directory (if compiled? "compiled.rkt" "observed.rkt")))
      (copy-file helper observed-file)
      (when compiled? (managed-compile-zo observed-file) (module-cache-clear!))
      (define namespace (make-base-namespace))
      (call-with-module-observation
        (lambda ()
          (parameterize ([current-namespace namespace])
            (dynamic-require observed-file #f)
            (for ([suffix '((early) (early nested) (late))])
              (dynamic-require `(submod ,observed-file ,@suffix) 'greeting)
              (define identity (make-resolved-module-path (cons observed-file suffix)))
              (check-true (compiled-module-expression? (observed-module-code identity namespace))))
            (check-equal?
              (module-compiled-name (observed-module-code (make-resolved-module-path observed-file) namespace))
              (if compiled? 'compiled 'observed))))))))
  (lambda () (delete-directory/files directory)))
