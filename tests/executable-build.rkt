#lang racket/base
(require rackunit racket/string mcp/workflow mcp/schema
         (submod mcp/workflow private) mcp/private/executable-build
         mcp/private/executable-capture racket/file)
(define build (make-executable-build))
(define stages (list (workflow-stage 'done 'complete Any (lambda (_) "done") #f #f)))
(define workflow (parameterize ([current-executable-build build])
                   (make-workflow "example" "1" "source/1" stages)))
(define copied (workflow-add-fingerprint-suffix workflow ":renderer/1"))
(check-true (workflow-descriptor? workflow))
(check-exn #rx"not sealed" (lambda () (workflow-executable-fingerprint workflow (hash))))
(check-exn #rx"not sealed" (lambda () (workflow-executable-fingerprint copied (hash))))
(define input-fingerprint (string-copy "build/1"))
(seal-executable-build! build input-fingerprint)
(string-set! input-fingerprint 0 #\X)
(check-equal? (workflow-executable-fingerprint workflow (hash)) "source/1:build:build/1")
(check-equal? (workflow-executable-fingerprint copied (hash)) "source/1:renderer/1:build:build/1")
(check-exn #rx"already sealed" (lambda () (seal-executable-build! build "replacement")))
(define plain (make-workflow "plain" "1" "explicit-data-api-fingerprint" stages))
(check-equal? (workflow-executable-fingerprint plain (hash)) "explicit-data-api-fingerprint")
;; Competing finalizers cannot replace the winner's immutable identity.
(define competing (make-executable-build))
(define results (make-channel))
(define workers
  (for/list ([fingerprint '("first" "second")])
    (thread (lambda ()
              (channel-put results
                (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                  (seal-executable-build! competing fingerprint)
                  fingerprint))))))
(define outcomes (list (channel-get results) (channel-get results)))
(for-each thread-wait workers)
(check-equal? (length (filter string? outcomes)) 1)
(check-equal? (length (filter (lambda (v) (eq? v 'rejected)) outcomes)) 1)
(check-equal? (executable-build-fingerprint competing) (car (filter string? outcomes)))
(define directory (make-temporary-file "mcp-seal-capture-~a" 'directory))
(dynamic-wind void
  (lambda ()
    (define path (build-path directory "example.rkt"))
    (call-with-output-file path
      (lambda (out) (display "#lang racket/base\n(provide value)\n(define value 7)\n" out)))
    (define capture (capture-module-export path 'value))
    (check-exn #rx"explicit identities" (lambda () (seal-module-code-capture! capture)))
    (check-exn exn:fail:contract?
      (lambda () (seal-module-code-capture! capture #:dependencies (hash "bad" #f))))
    (check-true (immutable? (module-code-capture-observed capture)))
    (for ([(name digest) (in-hash (module-code-capture-observed capture))])
      (check-true (immutable? name)) (check-true (immutable? digest)))
    (define sealed
      (seal-module-code-capture! capture
        #:dependencies (for/hash ([name (in-list (module-code-capture-unobserved capture))])
                         (values name "explicit-test-bootstrap/1"))))
    (check-true (string-prefix? sealed "mcp-executable/2:"))
    (check-exn #rx"already sealed"
      (lambda ()
        (seal-module-code-capture! capture
          #:dependencies (for/hash ([name (in-list (module-code-capture-unobserved capture))])
                           (values name "different-bootstrap"))))))
  (lambda () (delete-directory/files directory)))
