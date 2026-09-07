#lang racket/base
(require rackunit racket/file mcp/private/module-identity
         mcp/private/executable-capture mcp/private/executable-build)
(define predefined (make-resolved-module-path '#%kernel))
(define fresh (make-resolved-module-path (string->uninterned-symbol "#%kernel")))
(define unreadable (make-resolved-module-path (string->unreadable-symbol "#%kernel")))
(check-false (equal? predefined fresh))
(check-equal? (format "~s" (resolved-module-path-name predefined))
              (format "~s" (resolved-module-path-name fresh)))
(check-equal? (module-identity-key predefined) "#%kernel")
(check-true (immutable? (module-identity-key predefined)))
(check-exn #rx"portable provenance" (lambda () (module-identity-key fresh)))
(check-exn #rx"portable provenance" (lambda () (module-identity-key unreadable)))
(define owner (path->complete-path "identity-fixture.rkt"))
(check-equal? (module-identity-key (make-resolved-module-path (list owner 'child)))
              (format "~s" (list owner 'child)))
(check-exn #rx"portable provenance"
  (lambda () (module-identity-key (make-resolved-module-path
                                  (list owner (string->uninterned-symbol "child"))))))
;; This namespace contains an unrelated declaration whose printed name collides
;; with a predefined module included in the sealed build. It must not execute.
(define directory (make-temporary-file "mcp-symbolic-identity-~a" 'directory))
(define root (build-path directory "root.rkt"))
(define marker (build-path directory "called.txt"))
(define namespace (make-base-namespace))
(define fake-name (resolved-module-path-name fresh))
(dynamic-wind void
  (lambda ()
    (parameterize ([current-namespace namespace])
      (eval `(module ,fake-name racket/base
               (provide touch)
               (define (touch)
                 (call-with-output-file ,(path->string marker)
                   (lambda (out) (display "uncaptured code" out)))))))
    (call-with-output-file root
      (lambda (out) (display "#lang racket/base\n(provide value)\n(define value 1)\n" out)))
    (define capture (capture-module-export root 'value #:namespace namespace))
    (check-not-false (member "#%kernel" (module-code-capture-unobserved capture)))
    (void (seal-module-code-capture! capture #:dependencies
            (for/hash ([name (in-list (module-code-capture-unobserved capture))])
              (values name "explicit-test-bootstrap/1"))))
    (check-exn #rx"portable provenance"
      (lambda ()
        (call-with-executable-build (module-code-capture-build capture)
          (lambda () ((dynamic-require fresh 'touch))))))
    (check-false (file-exists? marker))
    ;; Direct capture of the symbolic declaration cannot reuse the kernel's key.
    (check-exn #rx"portable provenance"
      (lambda () (capture-module-export `(quote ,fake-name) 'touch #:namespace namespace)))
    (check-false (file-exists? marker)))
  (lambda () (delete-directory/files directory)))
