#lang racket/base

(provide (struct-out declaration-node) parse-declaration)
;; This IR contains lexical identifiers and complete source syntax. Only the
;; final manifest conversion discards syntax objects; handlers are never expanded
;; or evaluated here to infer metadata.
(struct declaration-node (kind name source arguments clauses value) #:transparent)
(define (parse-declaration kind name source)
  (define parts (syntax->list source))
  (define signature (and (pair? (cdr parts)) (syntax->list (cadr parts))))
  (define arguments (if (and signature (memq kind '(tool workflow resource prompt))) (cdr signature) '()))
  (define clauses
    (let loop ([rest (if (memq kind '(server)) (cdr parts) (cddr parts))] [out (hasheq)])
      (if (and (pair? rest) (keyword? (syntax-e (car rest))) (pair? (cdr rest)))
          (loop (cddr rest) (hash-set out (syntax-e (car rest)) (cadr rest))) out)))
  (declaration-node kind name source arguments clauses
                    (case kind [(schema) (caddr parts)] [(shape) (cddr parts)]
                      [(completion) (cadr signature)] [else #f])))
