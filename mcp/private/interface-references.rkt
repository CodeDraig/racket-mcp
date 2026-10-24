#lang racket/base
(require racket/list "descriptor-types.rkt" "handler-info.rkt" "../completion.rkt")
(provide resolve-interface-completions resolve-interface-references)
(define (resolve-interface-completions completions resources prompts)
  (define completion-routes (make-hasheq))
  (for/list ([completion (in-list completions)])
    (unless (completion-descriptor? completion)
      (raise-argument-error 'make-interface "completion-descriptor?" completion))
    (define original (completion-descriptor-target completion))
    (define target
      (if (resource-descriptor? original)
          (let ([candidates
                 (filter (lambda (resource)
                           (eq? (resource-descriptor-identity resource)
                                (resource-descriptor-identity original))) resources)])
            (when (null? candidates) (error 'make-interface "completion references an absent resource"))
            (unless (null? (cdr candidates))
              (error 'make-interface "completion references an ambiguous mounted resource"))
            (car candidates))
          (if (prompt-descriptor? original)
              (let ([candidates
                     (filter (lambda (prompt)
                               (eq? (prompt-declaration-identity prompt)
                                    (prompt-declaration-identity original))) prompts)])
                (when (null? candidates) (error 'make-interface "completion references an absent prompt"))
                (unless (null? (cdr candidates))
                  (error 'make-interface "completion references an ambiguous mounted prompt"))
                (car candidates)) original)))
    (define argument-name* (completion-descriptor-argument completion))
    (define arguments
      (cond [(resource-descriptor? target)
             (unless (memq target resources) (error 'make-interface "completion references an absent resource"))
             (resource-descriptor-arguments target)]
            [(prompt-descriptor? target)
             (unless (memq target prompts) (error 'make-interface "completion references an absent prompt"))
             (prompt-descriptor-arguments target)]
            [else (error 'make-interface "completion target must be a resource or prompt")]))
    (unless (memq argument-name* (map argument-name arguments))
      (error 'make-interface "completion references an unknown argument: ~a" argument-name*))
    (define previous (hash-ref completion-routes target '()))
    (when (memq argument-name* previous)
      (error 'make-interface "duplicate completion for argument: ~a" argument-name*))
    (hash-set! completion-routes target (cons argument-name* previous))
    (if (eq? target original) completion
        (struct-copy completion-descriptor completion [target target]))))
(define (resolve-interface-references references declarations resources)
  (define collected-references
    (for/fold ([collected (for/hasheq ([(source targets) (in-hash references)])
                           (values source targets))])
              ([source (in-list declarations)])
      (define handler
        (cond [(tool-descriptor? source) (tool-descriptor-handler source)]
              [(resource-descriptor? source) (resource-descriptor-handler source)]
              [else (prompt-descriptor-handler source)]))
      (define workflow
        (cond [(tool-descriptor? source) (tool-descriptor-workflow source)]
              [(resource-descriptor? source) (resource-descriptor-workflow source)]
              [else (prompt-descriptor-workflow source)]))
      (define inferred (append (handler-resource-references handler)
                               (handler-resource-references workflow)))
      (if (null? inferred) collected
          (hash-update collected source (lambda (targets) (append targets inferred)) '()))))
  (define checked-references
    (for/hasheq ([(source targets) (in-hash collected-references)])
      (unless (memq source declarations) (error 'make-interface "resource-reference source is an absent declaration"))
      (define source-name
        (cond [(tool-descriptor? source) (tool-descriptor-name source)]
              [(resource-descriptor? source) (resource-descriptor-name source)]
              [else (prompt-descriptor-name source)]))
      (unless (and (list? targets) (andmap resource-descriptor? targets))
        (error 'make-interface "resource references must be a list of resource descriptors"))
      (define resolved
        (for/list ([target (in-list targets)])
          (define candidates
            (filter (lambda (resource) (eq? (resource-descriptor-identity resource) (resource-descriptor-identity target))) resources))
          (when (null? candidates)
            (error 'make-interface "declaration ~a references an absent resource: ~a" source-name (resource-descriptor-name target)))
          (unless (null? (cdr candidates))
            (error 'make-interface "declaration ~a references an ambiguous mounted resource: ~a" source-name (resource-descriptor-name target)))
          (car candidates)))
      (values source (remove-duplicates resolved eq?))))
  checked-references)
