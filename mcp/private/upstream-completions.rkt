#lang racket/base
(require racket/list "../descriptor.rkt" "../completion.rkt")
(provide make-upstream-completions)
(define (make-upstream-completions snapshot resources prompts invoke)
  (define completions
    (if (hash-has-key? (hash-ref (hash-ref snapshot 'server/discover) 'capabilities) 'completions)
        (append-map
          (lambda (target)
            (define resource? (resource-descriptor? target))
            (define arguments (if resource? (resource-descriptor-arguments target) (prompt-descriptor-arguments target)))
            (define ref (if resource?
                            (hasheq 'type "ref/resource" 'uri (resource-descriptor-uri target))
                            (hasheq 'type "ref/prompt" 'name (prompt-descriptor-name target))))
            (for/list ([argument (in-list arguments)])
              (completion-descriptor target (argument-name argument)
                (lambda (prefix context)
                  (hash-ref (invoke "completion/complete"
                    (hasheq 'ref ref 'argument (hasheq 'name (symbol->string (argument-name argument)) 'value prefix)
                            'context context)) 'completion)))))
          (append resources prompts))
        '()))
  completions)
