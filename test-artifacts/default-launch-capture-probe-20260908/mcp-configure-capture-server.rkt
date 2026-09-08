#lang mcp
(require mcp/private/module-observation mcp/private/module-imports
         mcp/private/declared-code-capture mcp/private/executable-capture)
(server #:name "command-observation" #:version "1")
(define-namespace-anchor home)
(define owner (variable-reference->resolved-module-path (#%variable-reference)))
(tool (observed-build)
  #:description "Report observation coverage for this running module graph."
  (define visited (make-hasheq))
  (define missing '())
  (define ordinary 0)
  (define predefined 0)
  (define (visit identity)
    (unless (hash-ref visited identity #f)
      (hash-set! visited identity #t)
      (cond [(module-predefined? identity) (set! predefined (add1 predefined))]
            [else
             (set! ordinary (add1 ordinary))
             (unless (observed-module-code identity)
               (set! missing (cons (format "~a" (resolved-module-path-name identity)) missing)))])
      (when (module-declared? identity #f)
        (for-each visit (resolved-module-imports identity)))))
  (parameterize ([current-namespace (namespace-anchor->namespace home)]) (visit owner))
  (text-result (format "~s" (list ordinary predefined missing))))

(tool (capture-baseline)
  #:description "Report dependencies without executable identities in the frozen graph."
  (define capture
    (capture-declared-module-code owner #:namespace (namespace-anchor->namespace home)))
  (define missing (module-code-capture-unobserved capture))
  (define predefined (module-code-capture-predefined capture))
  (text-result
    (format "~s" (list missing predefined
                       (filter (lambda (name) (not (member name predefined))) missing)))))

(module configure-runtime '#%kernel
  (#%app (#%app dynamic-require 'mcp/private/module-observation 'install-module-observation!)))
