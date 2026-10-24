#lang racket/base
(require "descriptor-types.rkt" "declaration-contract.rkt" "../schema.rkt" "../json.rkt"
         "../uri-template.rkt" "../header-schema.rkt" "../presentation.rkt")
(provide make-tool make-resource make-prompt)
(define (make-tool name arguments handler #:description [description ""] #:output [output missing] #:annotations [annotations (hasheq)] #:workflow [workflow #f] #:execution [execution 'mrtr]
                   #:input-schema [input-schema missing] #:raw? [raw? #f] #:changes [changes (lambda (_args _result) '())])
  (check-arguments! 'make-tool arguments)
  (define normalized-output (if (missing? output) #f (schema-object output)))
  (check-tool-output! normalized-output)
  (define input
    (cond [(missing? input-schema)
           (object-schema (for/hasheq ([a (in-list arguments)]) (values (argument-name a) (argument-schema a)))
                          #:required (for/list ([a (in-list arguments)] #:unless (argument-optional? a)) (symbol->string (argument-name a))))]
          [(boolean? input-schema) (hash-set (schema-object input-schema) 'type "object")]
          [else input-schema]))
  (check-tool-input! input) (header-bindings input)
  (define descriptor (tool-descriptor name description arguments
                   input normalized-output handler annotations workflow execution raw? changes))
  (check-tool-contract! 'make-tool descriptor)
  descriptor)
(define (make-resource name uri handler #:description [description ""] #:mime-type [mime-type #f] #:render [renderer #f]
                       #:arguments [arguments '()] #:matcher [matcher #f] #:workflow [workflow #f] #:depends-on [depends-on (lambda (_args) '())] #:ttl-ms [ttl-ms 0])
  (check-arguments! 'make-resource arguments)
  (check-resource-template! uri arguments)
  (when renderer
    (unless (resource-renderer? renderer) (error 'make-resource "expected a named resource renderer"))
    (when (and mime-type (not (equal? mime-type (resource-renderer-mime-type renderer))))
      (error 'make-resource "resource and renderer MIME types disagree")))
  (define descriptor
    (resource-descriptor name uri description (or mime-type (and renderer (resource-renderer-mime-type renderer)) "text/plain")
                         handler arguments (or matcher (uri-template-matcher uri)) (gensym 'resource) workflow renderer depends-on ttl-ms))
  (check-resource-contract! 'make-resource descriptor)
  descriptor)
(define (make-prompt name arguments handler #:description [description ""] #:workflow [workflow #f])
  (check-arguments! 'make-prompt arguments)
  (define descriptor (prompt-descriptor name description arguments handler workflow))
  (check-prompt-contract! 'make-prompt descriptor)
  descriptor)
