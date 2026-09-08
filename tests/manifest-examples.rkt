#lang racket/base
(require rackunit racket/file racket/port racket/string mcp/cli)
(define directory (make-temporary-file "mcp-manifest-examples-~a" 'directory))
(dynamic-wind void
  (lambda ()
    (define source (build-path directory "examples.rkt"))
    (display-to-file
#<<APPLICATION
#lang mcp
(require (only-in mcp [scenario interaction]))
(tool (greet [name String]) (text-result name))
(error 'application "must not instantiate for documentation")
(scenario basic (error 'scenario "must not run"))
(interaction (configured session)
  #:interface (error 'configuration "must not evaluate")
  (error 'body "must not run"))
(scenario (process child) #:command (error 'command "must not launch")
  (error 'body "must not run"))
(define-syntax-rule (example) (scenario generated (error 'generated "must not run")))
(example)
APPLICATION
      source)
    (define manifest (read-manifest source))
    (check-equal? (map (lambda (entry) (hash-ref entry 'kind)) manifest) '(tool))
    (define examples (read-manifest-examples source))
    (check-equal? (map (lambda (entry) (hash-ref entry 'name)) examples) '(basic configured process generated))
    (for ([entry examples])
      (check-true (string? (hash-ref entry 'code)))
      (check-true (exact-positive-integer? (hash-ref entry 'line))))
    (check-true (string-contains? (hash-ref (cadr examples) 'code) "interaction"))
    (define text (manifest->markdown manifest #:examples examples))
    (check-true (string-contains? text "## Authored interaction examples"))
    (check-true (string-contains? text "source examples, not results of a test run"))
    (check-true (string-contains? text "#:command"))
    (check-false (string-contains? text "must not instantiate")) ; unrelated parent initialization is not an example
    (define command-output
      (parameterize ([current-command-line-arguments (vector "docs" (path->string source))])
        (with-output-to-string main)))
    (check-true (string-contains? command-output "Authored interaction examples"))
    (check-true (string-contains? command-output "must not launch"))
    (define legacy (build-path directory "legacy.rkt"))
    (display-to-file "#lang racket/base\n(error 'parent \"must not instantiate\")\n(module manifest racket/base (provide manifest) (define manifest '()))\n" legacy)
    (check-equal? (read-manifest-examples legacy) '())
    (define escaped (manifest->markdown '() #:examples
                      (list (hasheq 'name "example`name" 'code "(display \"```\")\n<script>"))))
    (check-true (string-contains? escaped "````racket\n"))
    (check-exn exn:fail:contract? (lambda () (manifest->markdown '() #:examples '(#f)))))
  (lambda () (delete-directory/files directory)))
