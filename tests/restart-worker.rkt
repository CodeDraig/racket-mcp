#lang racket/base
(require mcp racket/file)
(module+ main
  (define args (current-command-line-arguments))
  (define store (open-sqlite-store (vector-ref args 0)))
  (define marker (vector-ref args 1))
  (define flow
    (make-workflow "crash" "1" "fingerprint"
      (list (workflow-stage 'saved 'checkpoint Integer (lambda (_) 42) #f #f)
            (workflow-stage 'mutation 'effect Integer (lambda (_) 7) 'write 'manual)
            (workflow-stage 'done 'complete Any (lambda (env) (structured-result env)) #f #f)) #:key (lambda (_) "one")))
  (with-handlers ([exn:fail:recovery? (lambda (e) (displayln (exn:fail:recovery-handle e)) (close-store! store) (exit 8))])
    (define result
      (run-workflow flow store (hasheq) #:principal "alice"
                    #:adapters (hasheq 'write (effect-adapter 'manual
                                                (lambda (input key conn)
                                                  (call-with-output-file marker #:exists 'append (lambda (out) (displayln "mutation" out)))
                                                  (exit 9))))))
    (write-json result) (newline) (close-store! store)))
