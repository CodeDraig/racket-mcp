#lang racket/base
(require rackunit racket/port)
(define forms
  '("(tool (demo [a String] [b String]) (text-result a))"
    "(resource (demo [a String] [b String]) #:uri \"test:///{value}\" a)"
    "(prompt (demo [a String] [b String]) (role \"user\" a))"
    "(workflow (demo [a String] [b String]) #:version \"1\" (text-result a))"
    "(shape Demo [a String] [b String])"))
(for ([form (in-list forms)])
  (define input
    (format "(module declaration mcp/lang
      (require (for-syntax racket/base))
      (define-syntax (declare stx)
        (define first (datum->syntax stx 'value '(wire-binders.rkt 20 2 200 5)))
        (define second ((make-syntax-introducer)
          (datum->syntax stx 'value '(wire-binders.rkt 21 2 210 5))))
        (with-syntax ([a first] [b second]) #'~a))
      (declare))" form))
  (define failure
    (with-handlers ([exn:fail:syntax? values])
      (parameterize ([current-namespace (make-base-namespace)])
        (expand (read-syntax 'declaration.rkt (open-input-string input))))
      #f))
  (check-true (exn:fail:syntax? failure) form)
  (when (exn:fail:syntax? failure)
    (check-regexp-match #rx"duplicate.*wire name" (exn-message failure))
    (define source (car (exn:fail:syntax-exprs failure)))
    (check-equal? (syntax-e source) 'value)
    (check-equal? (syntax-source source) 'wire-binders.rkt)
    (check-equal? (syntax-line source) 21)))
