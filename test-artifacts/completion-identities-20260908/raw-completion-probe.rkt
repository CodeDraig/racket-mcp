#lang racket/base
(require rackunit mcp mcp/completion)
(resource (document [id String]) #:uri "old:///{id}" "body")
(define transformed (view (make-interface #:resources (list document)) #:uris (hash "old:///{id}" "new:///{id}")))
(define raw (interface-descriptor #f '() (interface-descriptor-resources transformed) '()
              (list (completion-descriptor document 'id (lambda (value context) '("ok"))))))
(check-equal?
 (hash-ref (hash-ref (dispatch (make-runtime raw) "completion/complete"
                      (hasheq '_meta (request-meta) 'ref (hasheq 'type "ref/resource" 'uri "new:///{id}")
                              'argument (hasheq 'name "id" 'value ""))) 'completion) 'values)
 '("ok"))
