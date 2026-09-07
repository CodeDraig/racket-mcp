#lang racket/base
(require (for-template racket/base))
(provide make-module-compilers)
;; Each module owns a lexical collector/finalizer pair. No process-wide table
;; communicates between modules or transformer instances.
(define (make-module-compilers runtime-register)
  (define entries '())
  (values
   (lambda (stx)
     (syntax-case stx ()
       [(_ descriptor info)
        (begin (set! entries (cons (cadr (syntax->datum #'info)) entries))
               #`(#,runtime-register descriptor))]
       [(_ descriptor) #`(#,runtime-register descriptor)]))
   (lambda (stx)
     #`(module manifest racket/base (provide manifest) (define manifest '#,(reverse entries))))))
