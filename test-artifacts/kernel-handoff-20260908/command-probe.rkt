(module command '#%kernel
  (#%require (file "/srv/data/code/racket-mcp/mcp/private/kernel-observation.rkt"))
  (#%provide main)
  (define-values (main)
    (lambda ()
      (call-with-kernel-observation
        (lambda (transfer!)
          (let-values ([(scoped) (dynamic-require 'mcp/private/module-observation 'call-with-module-observation)]
                       [(keyword-call) (dynamic-require 'racket/base 'keyword-apply)])
            (keyword-call scoped '(#:handoff) (list transfer!)
              (list (lambda () ((dynamic-require 'mcp/cli 'main))))))))))
  (module* main #f (main)))
