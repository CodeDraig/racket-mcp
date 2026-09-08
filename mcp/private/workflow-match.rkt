#lang racket/base
(require racket/match/parse racket/match/gen-match
         (only-in racket/match/patterns bound-vars)
         (for-template racket/base))
(provide compile-match-capture)

;; Keep Racket's private pattern representations entirely inside this compiler
;; adapter. Parse each pattern once: match expanders may introduce fresh scopes,
;; so discovering bindings and then expanding the pattern again is incorrect.
;; The same parsed patterns supply both the lexical names and generated matcher.
;; This adapter is checked on both supported Racket releases.
(define (compile-match-capture source subject patterns)
  (define parsed (map parse patterns))
  (define names (map bound-vars parsed))
  (define clauses
    (for/list ([ids (in-list names)] [index (in-naturals)])
      #`[#,index (list #,index (list #,@ids))]))
  (values
   (go/one (lambda (placeholder) (list-ref parsed (syntax-e placeholder)))
           source subject #`(#,@clauses))
   names))
