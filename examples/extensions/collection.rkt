#lang racket/base
(require mcp (for-syntax racket/base racket/syntax syntax/parse))
(provide collection)
(define-mcp-extension collection
  (syntax-parser
    [(_ name:id #:uri uri:str #:entries entries:expr)
     #:with search (format-id #'name #:source #'name "search-~a" #'name)
     #'(begin
         (define data entries)
         (resource (name [id String]) #:uri uri (hash-ref data id))
         (tool (search [query String])
           (structured-result (for/list ([(id value) (in-hash data)] #:when (regexp-match? (regexp-quote query) value)) id)))
         (completion (name id) (lambda (prefix context) (filter (lambda (id) (regexp-match? (regexp (string-append "^" (regexp-quote prefix))) id)) (hash-keys data)))))]))
