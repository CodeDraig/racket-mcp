(module command '#%kernel
  ;; Importing this entry must not load the ordinary SDK/runtime libraries.
  ;; Start observation before dynamically loading their first dependency.
  (#%require "private/kernel-observation.rkt")
  (#%provide main)
  (define-values (home)
    (variable-reference->module-path-index (#%variable-reference)))
  (define-values (main)
    (lambda ()
      (call-with-kernel-observation
        (lambda (transfer!)
          (let-values ([(scoped)
                        (dynamic-require
                          (module-path-index-resolve
                            (module-path-index-join "private/module-observation.rkt" home))
                          'call-with-module-observation)]
                       [(keyword-call) (dynamic-require 'racket/base 'keyword-apply)])
            (keyword-call scoped '(#:handoff) (list transfer!)
              (list
                (lambda ()
                  ((dynamic-require
                     (module-path-index-resolve (module-path-index-join "cli.rkt" home))
                     'main))))))))))
  (module* main #f (main)))
