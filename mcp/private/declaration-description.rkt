#lang racket/base
(require syntax/parse "declaration-ir.rkt" (for-template racket/base "../schema.rkt"))
(provide unknown literal source-fields make-declaration-description)
(define unknown (gensym 'unknown))
(define (literal stx)
  (define datum (syntax->datum stx))
  (cond [(or (string? datum) (boolean? datum) (number? datum) (hash? datum)) datum]
        [else (syntax-parse stx #:literals (quote)
                [(quote value) (syntax->datum #'value)] [_ unknown])]))
(define (source-fields stx)
  (hasheq 'source (format "~a" (syntax-source stx)) 'line (syntax-line stx)
          'column (syntax-column stx) 'position (syntax-position stx) 'span (syntax-span stx)))
(define (make-declaration-description nodes)
  (define (schema-value stx [seen '()])
    (define basic
      (for/or ([id (in-list (list #'String #'Integer #'Number #'Boolean #'Null #'Any))]
               [value (in-list (list (hasheq 'type "string") (hasheq 'type "integer") (hasheq 'type "number") (hasheq 'type "boolean") (hasheq 'type "null") #t))])
        (and (identifier? stx) (free-identifier=? id stx) (cons #t value))))
    (cond [basic (cdr basic)]
          [(identifier? stx)
           (define node (findf (lambda (node) (and (memq (declaration-node-kind node) '(schema shape))
                                                 (free-identifier=? stx (declaration-node-name node)))) nodes))
           (cond [(not node) unknown]
                 [(memq node seen) (raise-syntax-error 'schema "cyclic schema alias" (declaration-node-source node) stx)]
                 [(eq? (declaration-node-kind node) 'schema) (schema-value (declaration-node-value node) (cons node seen))]
                 [else
                  (define fields (map syntax->list (declaration-node-value node)))
                  (define field-schemas (map (lambda (field) (schema-value (cadr field) (cons node seen))) fields))
                  (if (memq unknown field-schemas) unknown
                      (hasheq 'type "object" 'additionalProperties #f
                              'required (map (lambda (field) (symbol->string (syntax-e (car field)))) fields)
                              'properties (for/hasheq ([field (in-list fields)] [value (in-list field-schemas)])
                                            (values (syntax-e (car field)) value))))])]
          [else (literal stx)]))
  (define (describe stx [schema? #f])
    (define value ((if schema? schema-value literal) stx))
    (if (eq? value unknown)
        (hasheq 'known? #f 'expression (format "~s" (syntax->datum stx)))
        (hasheq 'known? #t 'value value)))
  describe)
