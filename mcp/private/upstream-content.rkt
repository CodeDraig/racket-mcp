#lang racket/base
(require "../descriptor.rkt")
(provide make-upstream-content-remapper)
(define (make-upstream-content-remapper resources)
  (define (local-reference uri)
    (define matches
      (filter values
        (for/list ([resource (in-list resources)])
          (define matched ((resource-descriptor-matcher resource) uri))
          (and matched (cons resource matched)))))
    (when (> (length matches) 1)
      (error 'upstream "ambiguous resource reference: ~a" uri))
    (and (pair? matches)
         (let* ([resource (caar matches)]
                [arguments (bind-arguments (resource-descriptor-arguments resource) (cdar matches))])
           (resource-ref resource
             (for/list ([argument (in-list (resource-descriptor-arguments resource))])
               (hash-ref arguments (argument-name argument)))))))
  (define (remap-uri uri)
    (define ref (local-reference uri))
    (if ref (resource-uri ref) uri))
  (define (remap-content content)
    (case (string->symbol (hash-ref content 'type))
      [(resource) (hash-set content 'resource
                   (hash-set (hash-ref content 'resource) 'uri
                     (remap-uri (hash-ref (hash-ref content 'resource) 'uri))))]
      [(resource_link)
       (define ref (local-reference (hash-ref content 'uri)))
       (if ref (hash-set* content 'uri (resource-uri ref) 'name (hash-ref (link ref) 'name)) content)]
      [else content]))
  (values remap-uri remap-content))
