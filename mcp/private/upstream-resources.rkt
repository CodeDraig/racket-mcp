#lang racket/base
(require "../descriptor.rkt"
         "../schema.rkt"
         "../json.rkt"
         "../uri-template.rkt"
         "../presentation.rkt"
         "upstream-invocation.rkt"
         "upstream-content.rkt")
(provide (struct-out upstream-template-adapter) upstream-resource-change-keys make-upstream-resources)
(struct upstream-template-adapter (arguments matcher) #:transparent)
(define (upstream-resource-change-keys interface uri)
  (unless (interface-descriptor? interface)
    (raise-argument-error 'upstream-resource-change-keys "interface-descriptor?" interface))
  (unless (string? uri) (raise-argument-error 'upstream-resource-change-keys "string?" uri))
  (define matches
    (filter values
      (for/list ([resource (in-list (interface-descriptor-resources interface))])
        (define arguments ((resource-descriptor-matcher resource) uri))
        (and arguments (cons resource arguments)))))
  (unless (= (length matches) 1)
    (error 'upstream-resource-change-keys "expected one resource matching URI ~s; found ~a" uri (length matches)))
  (define resource (caar matches))
  (define arguments (bind-arguments (resource-descriptor-arguments resource) (cdar matches)))
  (define keys ((resource-descriptor-depends-on resource) arguments))
  (unless (and (list? keys) (pair? keys) (json-value? keys)
               (andmap (lambda (key) (and (list? key) (= (length key) 3)
                                          (equal? (car key) "mcp/upstream-resource"))) keys))
    (error 'upstream-resource-change-keys "resource does not declare upstream change keys"))
  keys)
(define (make-upstream-resources snapshot templates invoke bridge freshness-source)
  (define (build-resource wire uri arguments matcher)
    (make-resource (hash-ref wire 'name) uri
      (durable-handler bridge (lambda supplied-values
        (define remote-uri (uri-template-expand uri
          (for/hasheq ([argument (in-list arguments)] [value (in-list supplied-values)])
            (values (argument-name argument) value))))
        (define result (invoke "resources/read" (hasheq 'uri remote-uri)))
        (if (pending? result) result
        (apply resource-contents
          (for/list ([content (in-list (hash-ref result 'contents))])
            (resource-content (hash-set content 'uri (remap-uri (hash-ref content 'uri)))))))))
      #:description (hash-ref wire 'description "") #:mime-type (hash-ref wire 'mimeType #f)
      #:arguments arguments #:matcher matcher
      #:depends-on
      (lambda (bound)
        (list (list "mcp/upstream-resource" freshness-source (uri-template-expand uri bound))))))
  (define resources
    (append
     (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'resources/list) 'resources))])
       (build-resource wire (hash-ref wire 'uri) '() #f))
     (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'resources/templates/list) 'resourceTemplates))])
       (define uri (hash-ref wire 'uriTemplate))
       (define adapter (hash-ref templates uri #f))
       (when (and adapter (not (upstream-template-adapter? adapter)))
         (error 'make-upstream-interface "Expected an upstream-template-adapter for ~a" uri))
       (define arguments
         (if adapter (upstream-template-adapter-arguments adapter)
             (for/list ([name (in-list (uri-template-variables uri))])
               (argument name String #f #f))))
       (build-resource wire uri arguments
         (if adapter (upstream-template-adapter-matcher adapter) (uri-template-matcher uri))))))
  (define-values (remap-uri remap-content) (make-upstream-content-remapper resources))
  (values resources remap-content))
