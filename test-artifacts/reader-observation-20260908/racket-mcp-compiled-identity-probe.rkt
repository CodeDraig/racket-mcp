#lang racket/base
(require racket/port file/sha1 rackunit)
(current-check-handler (lambda (failure) (raise failure)))
(define (stamp value)
  (parameterize ([current-namespace (make-base-namespace)])
    (define code (compile `(module application racket/base
      (provide value) (define value ,value) (displayln "APPLICATION INSTANTIATED")
      (module helper racket/base (provide text) (define text "nested")))))
    ;; Identity describes the compiler's input artifact. The added declaration is
    ;; producer metadata, not a claim to re-hash post-rewrite bytecode in place.
    (define identity (bytes->hex-string (sha256-bytes (open-input-bytes
      (call-with-output-bytes (lambda (out) (write code out)))))))
    (define metadata (module-compiled-name
      (compile `(module mcp-executable racket/base (provide identity)
        (define identity ,identity))) '(application mcp-executable)))
    (values identity (module-compiled-submodules code #t
      (append (module-compiled-submodules code #t) (list metadata))))))
(define-values (old-id old-code) (stamp "old"))
(define-values (new-id new-code) (stamp "new"))
(check-not-equal? old-id new-id)
(for* ([serialized? '(#f #t)] [entry (list (list old-id old-code "old") (list new-id new-code "new"))])
  (parameterize ([current-namespace (make-base-namespace)])
    (define code (cadr entry))
    (when serialized?
      (set! code (parameterize ([read-accept-compiled #t])
        (read (open-input-bytes (call-with-output-bytes (lambda (out) (write code out))))))))
    (eval code)
    (check-equal? (with-output-to-string
      (lambda () (check-equal? (dynamic-require '(submod 'application mcp-executable) 'identity) (car entry)))) "")
    (check-equal? (dynamic-require '(submod 'application helper) 'text) "nested")
    (check-equal? (with-output-to-string
      (lambda () (check-equal? (dynamic-require ''application 'value) (caddr entry))))
      "APPLICATION INSTANTIATED\n")))
(displayln "Producer identity, body changes, original submodules and parent-free inspection passed before and after serialization.")
