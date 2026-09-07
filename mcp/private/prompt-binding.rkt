#lang racket/base
(require (for-template racket/base))
(provide (struct-out prompt-binding) lookup-prompt-binding)
;; Preserve metadata through exports while referring to the hidden syntax-spec
;; operation binding in host expressions. Do not collapse exports into aliases.
(struct prompt-binding (target name arguments)
  #:property prop:procedure
  (lambda (self stx)
    (syntax-case stx ()
      [id (identifier? #'id) (prompt-binding-target self)]
      [(_ argument ...) #`(#,(prompt-binding-target self) argument ...)])))
(define (lookup-prompt-binding id)
  (with-handlers ([exn:fail:syntax? (lambda (_) #f)])
    (define value (syntax-local-value id (lambda () #f)))
    (and (prompt-binding? value) value)))
