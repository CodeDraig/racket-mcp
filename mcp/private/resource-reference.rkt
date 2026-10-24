#lang racket/base
(require "descriptor-types.rkt" "request-context.rkt" "../uri-template.rkt" "../rendering.rkt")
(provide resource-link resource-uri link embed)
(define (resource-link ref)
  (define d (resolve-resource ref))
  (hasheq 'type "resource_link" 'uri (resource-uri ref) 'name (resource-descriptor-name d) 'mimeType (resource-descriptor-mime-type d)))
(define (resolve-resource ref)
  (define original (resource-ref-declaration ref))
  (cond
    [(current-interface)
     (define candidates
       (filter (lambda (d) (eq? (resource-descriptor-identity original)
                                (resource-descriptor-identity d)))
               (interface-descriptor-resources (current-interface))))
     (cond [(null? candidates) (error 'resource-uri "referenced resource is absent from the interface")]
           [(pair? (cdr candidates)) (error 'resource-uri "referenced resource has ambiguous mounts in the interface")]
           [else (car candidates)])]
    [else original]))
(define (resource-uri ref)
  (define original (resource-ref-declaration ref))
  (define d (resolve-resource ref))
  (uri-template-expand (resource-descriptor-uri d)
                       (for/hasheq ([a (in-list (resource-descriptor-arguments original))] [v (in-list (resource-ref-arguments ref))])
                         (values (argument-name a) v))))
(define link resource-link)
(define (embed ref)
  (if (current-render-capture) (deferred-embedding (resource-uri ref)) ((current-resource-resolver) ref)))
