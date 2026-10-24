#lang racket/base
(require syntax/parse (for-template racket/base))
(provide unknown literal described wire-name)
(define unknown (gensym 'dynamic))
;; Interpret only this closed, binding-checked literal grammar. Never expand or
;; evaluate arbitrary Racket expressions to discover an interface or option.
(define (literal stx)
  (define datum (syntax->datum stx))
  (cond [(or (string? datum) (boolean? datum) (number? datum) (hash? datum)) datum]
        [else
         (syntax-parse stx #:literals (quote list hash hasheq hasheqv)
           [(quote datum) (syntax->datum #'datum)]
           [(list item ...)
            (define items (map literal (syntax->list #'(item ...))))
            (if (memq unknown items) unknown items)]
           [((~and constructor (~or hash hasheq hasheqv)) item ...)
            (define items (map literal (syntax->list #'(item ...))))
            (if (or (memq unknown items) (odd? (length items))) unknown
                (apply (cond [(free-identifier=? #'constructor #'hasheq) hasheq]
                             [(free-identifier=? #'constructor #'hasheqv) hasheqv] [else hash]) items))]
           [_ unknown])]))
(define (described stx)
  (define value (literal stx))
  (if (eq? value unknown) (hasheq 'known? #f 'expression (format "~s" (syntax->datum stx)))
      (hasheq 'known? #t 'value value)))
(define (wire-name name) (if (symbol? name) (symbol->string name) name))
