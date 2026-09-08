#lang racket/base
(require rackunit racket/file racket/port
         mcp/private/module-observation mcp/private/declared-code-capture
         mcp/private/executable-capture mcp/private/executable-build)
(define directory (make-temporary-file "mcp-declared-capture-~a" 'directory))
(define root (build-path directory "root.rkt"))
(define helper (build-path directory "helper.rkt"))
(define extra (build-path directory "extra.rkt"))
(define identity (make-resolved-module-path root))
(define (key path) (format "~s" path))
(define (write-file path text)
  (call-with-output-file path #:exists 'truncate (lambda (out) (display text out))))
(define (helper-value text)
  (write-file helper (format "#lang racket/base\n(provide value)\n(define value ~s)\n" text)))
(dynamic-wind void
  (lambda ()
    (helper-value "before")
    (write-file root "#lang racket/base\n(require \"helper.rkt\")\n(provide value)\n")
    (write-file extra "#lang racket/base\n(provide value)\n(define value 'extra)\n")
    (define first (make-base-namespace))
    (define second (make-base-namespace))
    (test-case "snapshots are registry-scoped and retain old loaded code"
      (check-exn #rx"not declared" (lambda () (capture-declared-module-code identity #:namespace first)))
      (call-with-module-observation
        (lambda ()
          (parameterize ([current-namespace first])
            (check-equal? (dynamic-require root 'value) "before"))
          (define snapshot (module-observation-snapshot first))
          (check-true (immutable? snapshot))
          (check-true (hash-has-key? snapshot identity))
          (check-equal? (module-observation-snapshot second) (hash))
          (define before (capture-declared-module-code identity #:namespace first #:value 'descriptor))
          (check-equal? (module-code-capture-value before) 'descriptor)
          (check-true (hash-has-key? (module-code-capture-observed before) (key helper)))
          (void
            (seal-module-code-capture! before
              #:dependencies
              (for/hash ([name (in-list (module-code-capture-unobserved before))])
                (values name "explicit-test-runtime/1"))))
          (helper-value "after")
          (define retained (capture-declared-module-code identity #:namespace first))
          (check-equal? (module-code-capture-observed before) (module-code-capture-observed retained))
          (check-equal?
            (call-with-executable-build (module-code-capture-build before)
              (lambda () (dynamic-require root 'value)))
            "before")
          (parameterize ([current-namespace second])
            (check-equal? (dynamic-require root 'value) "after"))
          (define changed (capture-declared-module-code identity #:namespace second))
          (check-not-equal? (hash-ref (module-code-capture-observed before) (key helper))
                            (hash-ref (module-code-capture-observed changed) (key helper)))
          (parameterize ([current-namespace first]) (dynamic-require extra #f))
          (check-exn #rx"not loaded in the sealed executable"
            (lambda ()
              (call-with-executable-build (module-code-capture-build before)
                (lambda () (dynamic-require extra 'value)))))
          (check-false (hash-has-key? snapshot (make-resolved-module-path extra)))
          (define extended (capture-declared-module-code identity #:namespace first))
          (check-true (hash-has-key? (module-code-capture-observed extended) (key extra)))
          (check-not-equal? (module-code-capture-unobserved extended) '())
          (check-exn #rx"explicit identities"
            (lambda () (seal-module-code-capture! extended))))))
    (test-case "declaration capture does not instantiate a throwing module"
      (define ns (make-base-namespace))
      (define bomb (make-resolved-module-path 'capture-bomb))
      (call-with-module-observation
        (lambda ()
          (parameterize ([current-namespace ns]
                         [current-module-declare-name bomb])
            (eval '(module capture-bomb racket/base
                     (error 'bomb "must not instantiate"))))
          (define capture (capture-declared-module-code bomb #:namespace ns))
          (check-true (hash-has-key? (module-code-capture-observed capture) (key 'capture-bomb))))))
    (test-case "unstamped preloaded modules remain unknown"
      (define ns (make-base-namespace))
      (parameterize ([current-namespace ns]) (dynamic-require root #f))
      (define capture (capture-declared-module-code identity #:namespace ns))
      (check-not-false (member (key root) (module-code-capture-unobserved capture)))
      (check-not-false (member (key helper) (module-code-capture-unobserved capture))))
    (test-case "a language module can freeze code during its own initialization"
      (define inside (build-path directory "inside.rkt"))
      (write-file inside
        (string-append
          "#lang mcp\n(require mcp/private/declared-code-capture mcp/private/executable-capture)\n"
          "(provide result)\n"
          "(define here (variable-reference->resolved-module-path (#%variable-reference)))\n"
          "(define capture (capture-declared-module-code here #:namespace (variable-reference->namespace (#%variable-reference))))\n"
          "(define result (hash-has-key? (module-code-capture-observed capture) (format \"~s\" (resolved-module-path-name here))))\n"))
      (parameterize ([current-namespace (make-base-namespace)])
        (check-true (dynamic-require inside 'result)))))
  (lambda () (delete-directory/files directory)))
