#lang racket/base
(require racket/list "declaration-ir.rkt" (for-template racket/base))
(provide make-module-compilers)
;; Each module owns a lexical collector/finalizer pair. No process-wide table
;; communicates between modules or transformer instances.
(define (make-module-compilers runtime-register)
  (define entries '())
  (define references '())
  (values
   (lambda (stx)
     (syntax-case stx ()
       [(_ descriptor #:references owner (target ...))
        (begin (set! references (cons (cons #'owner (syntax->list #'(target ...))) references)) #'(void))]
       [(_ descriptor #:declaration kind name source #:workflow-nodes (stage ...))
        (begin (set! entries (cons (struct-copy declaration-node (parse-declaration (syntax-e #'kind) #'name #'source)
                                              [value (syntax->list #'(stage ...))]) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor #:declaration kind name source)
        (begin (set! entries (cons (parse-declaration (syntax-e #'kind) #'name #'source) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor info)
        (begin (set! entries (cons (cadr (syntax->datum #'info)) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor) #`(#,runtime-register descriptor)]))
   (lambda (stx)
     (define ordered (reverse entries))
     (define nodes (filter declaration-node? ordered))
     (define compiled
       (for/list ([node (in-list nodes)] [entry (in-list (declarations->manifest nodes))])
         (define targets
           (append-map cdr (filter (lambda (group) (and (identifier? (declaration-node-name node)) (free-identifier=? (car group) (declaration-node-name node)))) references)))
         (define origins
           (remove-duplicates
            (for/list ([target (in-list targets)])
              (or (syntax-property target 'mcp-resource-origin) (hasheq 'name #f 'known? #f))) equal?))
         (if (memq (declaration-node-kind node) '(tool resource prompt workflow))
             (hash-set* entry 'resource-references (sort origins string<? #:key (lambda (origin) (format "~a:~a:~a" (hash-ref origin 'source "") (hash-ref origin 'position 0) (hash-ref origin 'name))))
                        'reference-analysis 'lexical-handler-syntax) entry)))
     ;; Called in the final generated RHS, after application RHS expansion.
     ;; Lift a fresh, independent module containing only quoted manifest data.
     (syntax-local-lift-module
      #`(module manifest racket/base (provide manifest manifest-version)
          (define manifest-version 2)
          (define manifest '#,(append compiled (filter (lambda (entry) (not (declaration-node? entry))) ordered)))))
     #'(void))))
