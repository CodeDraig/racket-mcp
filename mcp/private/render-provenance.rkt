#lang racket/base
(provide mark-render-value render-value-kind render-provenance restore-render-provenance)
;; An impersonator property cannot be acquired by decoding or copying JSON keys.
;; Hash contents remain ordinary JSON for schema validation and public codecs.
(define-values (prop:render marked? marker-kind) (make-impersonator-property 'mcp-render-value))
(define (render-value-kind value) (and (marked? value) (marker-kind value)))
(define (mark-render-value value kind)
  (unless (and (hash? value) (member kind '("embedding" "embedded")))
    (error 'mark-render-value "Invalid rendering value"))
  (chaperone-hash value
    (lambda (_ key) (values key (lambda (_ _key value) value)))
    (lambda (_ key value) (values key value))
    (lambda (_ key) key) (lambda (_ key) key)
    prop:render kind))
;; Sidecar paths are stored by the SDK in separate database columns. Application
;; JSON is never inspected for a self-declared provenance wrapper or key.
(define (render-provenance value)
  (define marks '())
  (define (walk value path)
    (when (render-value-kind value)
      (set! marks (cons (hasheq 'path (reverse path) 'kind (render-value-kind value)) marks)))
    (cond [(hash? value)
           (for ([(key child) (in-hash value)]) (walk child (cons (symbol->string key) path)))]
          [(list? value)
           (for ([child (in-list value)] [index (in-naturals)]) (walk child (cons index path)))]))
  (walk value '())
  (reverse marks))
(define (restore-render-provenance value marks)
  (define (at value path kind)
    (cond [(null? path) (mark-render-value value kind)]
          [(and (string? (car path)) (hash? value))
           (define key (string->symbol (car path)))
           (hash-set value key (at (hash-ref value key) (cdr path) kind))]
          [(and (exact-nonnegative-integer? (car path)) (list? value) (< (car path) (length value)))
           (for/list ([child (in-list value)] [index (in-naturals)])
             (if (= index (car path)) (at child (cdr path) kind) child))]
          [else (error 'restore-render-provenance "Invalid stored rendering path")]))
  (for/fold ([value value]) ([mark (in-list marks)])
    (at value (hash-ref mark 'path) (hash-ref mark 'kind))))
