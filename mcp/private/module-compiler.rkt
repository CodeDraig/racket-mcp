#lang racket/base
(require racket/list "declaration-ir.rkt" (for-template racket/base))
(provide make-module-compilers)
;; Each module owns a lexical collector/finalizer pair. No process-wide table
;; communicates between modules or transformer instances.
(define (make-module-compilers runtime-register)
  (define entries '())
  (values
   (lambda (stx)
     (syntax-case stx ()
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
     (define compiled (declarations->manifest (filter declaration-node? ordered)))
     #`(module manifest racket/base (provide manifest manifest-version)
         (define manifest-version 2)
         (define manifest '#,(append compiled (filter (lambda (entry) (not (declaration-node? entry))) ordered)))))))
