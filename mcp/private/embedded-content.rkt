#lang racket/base
(require racket/list "render-provenance.rkt")
(provide embedded-resource-content embedded-group? embedded-group-items
         expand-content-items expand-prompt-messages embedded-json)
(define (embedded-group? value)
  (and (equal? (render-value-kind value) "embedded") (hash? value) (= (hash-count value) 1)
       (list? (hash-ref value '$mcp/embedded #f))))
(define (embedded-group-items value) (hash-ref value '$mcp/embedded))
(define (embedded-resource-content result)
  (unless (and (hash? result) (equal? (hash-ref result 'resultType #f) "complete")
               (list? (hash-ref result 'contents #f)))
    (error 'embed "Expected a complete resource result"))
  (define items
    (for/list ([content (in-list (hash-ref result 'contents))])
      (unless (and (hash? content) (string? (hash-ref content 'uri #f))
                   (or (string? (hash-ref content 'text #f)) (string? (hash-ref content 'blob #f))))
        (error 'embed "Invalid resource content"))
      (hasheq 'type "resource" 'resource content)))
  (if (= (length items) 1) (car items) (mark-render-value (hasheq '$mcp/embedded items) "embedded")))
(define (expand-content-items items)
  (append-map (lambda (item) (if (embedded-group? item) (embedded-group-items item) (list item))) items))
(define (expand-prompt-messages messages)
  (append-map
   (lambda (message)
     (define content (and (hash? message) (hash-ref message 'content #f)))
     (if (embedded-group? content)
         (map (lambda (item) (hash-set message 'content item)) (embedded-group-items content))
         (list message))) messages))
;; In JSON presentations a multi-content embedding occupies one value: an array.
;; Only the explicit private group marker expands, not arbitrary nested lists.
(define (embedded-json value)
  (cond [(embedded-group? value) (map embedded-json (embedded-group-items value))]
        [(hash? value) (for/hasheq ([(k v) (in-hash value)]) (values k (embedded-json v)))]
        [(list? value) (map embedded-json value)]
        [else value]))
