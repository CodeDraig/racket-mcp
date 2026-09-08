(module kernel-observation-worker '#%kernel
  (#%require "../mcp/private/kernel-observation.rkt")
  (call-with-kernel-observation
    (lambda (transfer!)
      (let-values ([(scoped) (dynamic-require 'mcp/private/module-observation 'call-with-module-observation)]
                   [(observed) (dynamic-require 'mcp/private/module-observation 'observed-module-code)]
                   [(imports) (dynamic-require 'mcp/private/module-imports 'resolved-module-imports)]
                   [(keyword-call) (dynamic-require 'racket/base 'keyword-apply)]
                   [(target) (string->path (vector-ref (current-command-line-arguments) 0))])
        (keyword-call scoped '(#:handoff) (list transfer!)
          (list
            (lambda ()
              (dynamic-require target 'mcp-interface)
              (let-values ([(visited) (make-hasheq)] [(ordinary) 0] [(predefined) 0])
                (letrec-values
                  ([(visit)
                    (lambda (identity)
                      (if (hash-ref visited identity #f) (void)
                          (begin
                            (hash-set! visited identity #t)
                            (if (module-predefined? identity)
                                (set! predefined (add1 predefined))
                                (if (observed identity)
                                    (set! ordinary (add1 ordinary))
                                    (begin
                                      (write identity (current-error-port))
                                      (raise (exn:fail "ordinary module was not observed"
                                                       (current-continuation-marks))))))
                            (if (module-declared? identity #f)
                                (for-each visit (imports identity)) (void)))))])
                  (visit (module-path-index-resolve (module-path-index-join target #f)))
                  (write (list 'ordinary ordinary 'predefined predefined))
                  (newline))))))))))
