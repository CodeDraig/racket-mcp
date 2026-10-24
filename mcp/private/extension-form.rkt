#lang racket/base
(require "extensions.rkt" (for-syntax racket/base syntax/parse))
(provide define-mcp-extension)
(define-syntax (define-mcp-extension stx)
  (syntax-parse stx
    [(_ name:id #:workflow transformer:expr)
     #'(define-syntax name (workflow-extension transformer))]
    [(_ name:id #:declaration transformer:expr)
     (define hidden (car (generate-temporaries #'(name))))
     (with-syntax ([internal hidden])
       #'(begin
           (define-syntax internal (declaration-extension transformer))
           (define-syntax (name use)
             (syntax-case use ()
               [(_ . tail) (expand-declaration-extension #'(internal . tail))]))))]
    [(_ name:id transformer:expr)
     #'(define-mcp-extension name #:declaration transformer)]))
