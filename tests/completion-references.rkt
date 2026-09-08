#lang racket/base
(require rackunit racket/list racket/runtime-path mcp mcp/completion mcp/cli)
(prompt (choose [id String]) (role "user" (text-content id)))
(resource (document [id String]) #:uri "doc:///{id}" id)
(tool (operation [id String]) (text-result id))
(define evaluations 0)
(define handler-calls 0)
(define complete
  (completion (choose id)
    (begin (set! evaluations (add1 evaluations))
           (lambda (_prefix _context) (set! handler-calls (add1 handler-calls)) '("one")))))
(check-true (completion-descriptor? complete))
(check-equal? evaluations 1)
(check-equal? handler-calls 0)
(define iface (make-interface #:prompts (list choose) #:completions (list complete)))
(check-equal? (interface-descriptor-completions iface) (list complete))
(check-exn #rx"absent prompt" (lambda () (make-interface #:completions (list complete))))
(check-exn #rx"absent prompt"
  (lambda () (make-runtime (interface-descriptor #f '() '() '() (list complete)))))
(check-exn #rx"unknown argument"
  (lambda () (make-interface #:prompts (list choose)
               #:completions (list (completion-descriptor choose 'typo (lambda (_p _c) '()))))))
(check-exn #rx"target must be a resource or prompt"
  (lambda () (make-interface #:tools (list operation)
               #:completions (list (completion-descriptor operation 'id (lambda (_p _c) '()))))))
(check-exn #rx"duplicate completion"
  (lambda () (make-interface #:prompts (list choose) #:completions (list complete complete))))
(check-exn #rx"absent resource"
  (lambda () (make-interface #:completions (list (completion-descriptor document 'id (lambda (_p _c) '()))))))
(check-exn exn:fail:contract? (lambda () (completion-descriptor choose "id" values)))
(check-exn exn:fail:contract? (lambda () (completion-descriptor choose 'id (lambda (_) '()))))
(define remapped (view iface #:namespace "nested/"))
(check-eq? (completion-descriptor-target (car (interface-descriptor-completions remapped)))
           (car (interface-descriptor-prompts remapped)))
(check-exn #rx"duplicate published identity" (lambda () (mount-interfaces iface iface)))

;; Expansion uses local lexical declarations, including forward references,
;; without evaluating the handler expression.
(check-not-exn
 (lambda () (expand #'(module valid mcp/lang
                       (completion (choose id) (error 'handler "must not evaluate"))
                       (prompt (choose [id String]) '())))))
(define (syntax-error-at? pattern datum)
  (lambda (e)
    (and (exn:fail:syntax? e) (regexp-match? pattern (exn-message e))
         (for/or ([stx (in-list (exn:fail:syntax-exprs e))]) (equal? (syntax->datum stx) datum)))))
(check-exn (syntax-error-at? #rx"unknown target argument" 'typo)
 (lambda () (expand #'(module bad mcp/lang
                       (prompt (choose [id String]) '())
                       (completion (choose typo) values)))))
(check-exn (syntax-error-at? #rx"target must be a resource or prompt" 'operation)
 (lambda () (expand #'(module bad mcp/lang
                       (tool (operation [id String]) (text-result id))
                       (completion (operation id) values)))))
(check-exn #rx"duplicate statically known published identity"
 (lambda () (expand #'(module bad mcp/lang
                       (resource (document [id String]) #:uri "doc:///{id}" id)
                       (completion (document id) values)
                       (completion (document id) values)))))
(module manifest-fixture mcp/lang
  (prompt (choose [id String]) '())
  (completion (choose id) (error 'handler "manifest must not instantiate parent")))
(require (prefix-in fixture: (submod "." manifest-fixture manifest)))
(define entry (findf (lambda (d) (eq? (hash-ref d 'kind) 'completion)) fixture:manifest))
(check-equal? (hash-ref entry 'argument) 'id)
(check-equal? (hash-ref entry 'target) (hasheq 'known? #t 'kind 'prompt 'name 'choose))
(check-true (exact-positive-integer? (hash-ref entry 'position)))
(define another-entry (hash-set entry 'argument 'another))
(define prompt-entry (findf (lambda (d) (eq? (hash-ref d 'kind) 'prompt)) fixture:manifest))
(check-equal? (sort (map (lambda (d) (hash-ref d 'change))
                        (manifest-diff (list prompt-entry entry another-entry) (list prompt-entry another-entry))) string<?)
              '("breaking-removal" "static-manifest-unchanged" "static-manifest-unchanged"))

(module provider racket/base
  (require mcp)
  (provide remote)
  (prompt (remote [id String]) '()))
(module imported mcp/lang
  (require (rename-in (submod ".." provider) [remote renamed]))
  (mount (make-interface #:prompts (list renamed)))
  (completion (renamed id) (lambda (_prefix _context) '("imported"))))
(require (prefix-in imported: (submod "." imported))
         (prefix-in imported-manifest: (submod "." imported manifest)))
(check-equal? (length (interface-descriptor-completions imported:mcp-interface)) 1)
(define imported-entry (findf (lambda (d) (eq? (hash-ref d 'kind) 'completion)) imported-manifest:manifest))
(check-equal? (hash-ref imported-entry 'target) (hasheq 'known? #t 'kind 'prompt 'name 'remote))
(check-false (hash-ref imported-entry 'dynamic-metadata))
(module absent-import mcp/lang
  (require (rename-in (submod ".." provider) [remote renamed]))
  (completion (renamed id) (lambda (_prefix _context) '())))
(define-runtime-path self "completion-references.rkt")
(check-exn #rx"absent prompt"
 (lambda () (dynamic-require `(submod ,self absent-import) #f)))
;; Same-spelling host bindings must not resolve to a different local declaration.
(check-not-exn
 (lambda () (expand #'(module lexical mcp/lang
                       (prompt (choose [id String]) '())
                       (let ([choose 'host-value])
                         (completion (choose typo) values))))))
