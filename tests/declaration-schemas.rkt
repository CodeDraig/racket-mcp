#lang racket/base
(require rackunit racket/list mcp)
(define invalid #hasheq((type . "not-a-schema-type")))
(define source-forms
  (list #'(schema Bad #hasheq((type . "not-a-schema-type")))
        #'(tool (bad [value #hasheq((type . "not-a-schema-type"))]) (text-result "bad"))
        #'(tool (bad) #:output #hasheq((type . "not-a-schema-type")) (text-result "bad"))
        #'(resource (bad [value #hasheq((type . "not-a-schema-type"))]) #:uri "bad:///{value}" "bad")
        #'(prompt (bad [value #hasheq((type . "not-a-schema-type"))]) '())
        #'(shape Bad [value #hasheq((type . "not-a-schema-type"))])
        #'(workflow (bad [value #hasheq((type . "not-a-schema-type"))]) #:version "1" (text-result "bad"))
        #'(workflow (bad) #:version "1" (checkpoint [value #hasheq((type . "not-a-schema-type"))] 1) (text-result "bad"))
        #'(workflow (bad) #:version "1" (await-input [value #hasheq((type . "not-a-schema-type"))] 'request) (text-result "bad"))
        #'(workflow (bad) #:version "1" (await-input ([value #hasheq((type . "not-a-schema-type")) 'request])) (text-result "bad"))
        #'(workflow (bad) #:version "1" (perform [value #hasheq((type . "not-a-schema-type"))] #:adapter save #:policy manual 1) (text-result "bad"))))
(for ([form (in-list source-forms)])
  (check-exn
   (lambda (e) (and (exn:fail:syntax? e)
                    (for/or ([source (in-list (exn:fail:syntax-exprs e))])
                      (and (equal? (syntax->datum source) invalid)
                           (exact-positive-integer? (syntax-line source))))))
   (lambda () (expand #`(module bad-schema mcp/lang #,form)))))
(check-exn exn:fail:syntax? (lambda () (expand #'(tool (bad [x 'bogus]) (text-result "bad")))))
(check-exn exn:fail:syntax? (lambda () (expand #'(resource (bad [x 10]) #:uri "bad:///{x}" "bad"))))
(check-not-exn (lambda () (expand #'(tool (allowed [x #f]) (text-result "never")))))
(check-not-exn (lambda () (expand #'(schema Allowed #hasheq((format . "custom-annotation"))))))
;; Host computation is never evaluated to discover a schema during expansion.
(check-not-exn
 (lambda () (expand #'(module dynamic mcp/lang
                       (resource (dynamic [x (error 'schema "instantiation only")]) #:uri "dynamic:///{x}" "")))))
(define evaluations '())
(define (record name value) (set! evaluations (append evaluations (list name))) value)
(resource (ordered [first (record 'first Integer)]
                   [second (record 'second Integer) #:default (record 'default (add1 first))])
  #:uri "ordered:///{first}/{second}" (number->string second))
(check-equal? evaluations '(first second))
(define bound (bind-arguments (resource-descriptor-arguments ordered) (hasheq 'first 3)))
(check-equal? bound (hasheq 'first 3 'second 4))
(check-equal? evaluations '(first second default))

(define constructors
  (list (lambda (args) (make-tool "dynamic" args values))
        (lambda (args) (make-resource "dynamic" "dynamic:///" values #:arguments args))
        (lambda (args) (make-prompt "dynamic" args values))))
(for ([construct (in-list constructors)])
  (check-exn exn:fail:schema? (lambda () (construct (list (argument 'value invalid #f #f)))))
  (check-exn #rx"duplicate argument"
    (lambda () (construct (list (argument 'value String #f #f) (argument 'value String #t #f)))))
  (check-exn #rx"name must be a symbol" (lambda () (construct (list (argument "value" String #f #f)))))
  (check-exn #rx"flag must be a boolean" (lambda () (construct (list (argument 'value String 1 #f)))))
  (check-exn #rx"default must accept" (lambda () (construct (list (argument 'value String #t (lambda () "bad"))))))
  (check-exn #rx"with a default must be optional" (lambda () (construct (list (argument 'value String #f values)))))
  (check-exn exn:fail:contract? (lambda () (construct '(not-an-argument))))
  (check-not-exn (lambda () (construct (list (argument 'value String #t (lambda (_earlier) "default")))))))
(check-exn #rx"nonempty wire name" (lambda () (make-resource "" "empty:///" values)))

;; Raw public descriptors must not defer malformed schemas until dispatch.
(define good-resource (make-resource "raw" "raw:///" values))
(define raw-resource
  (struct-copy resource-descriptor good-resource
    [arguments (list (argument 'value invalid #f #f))]))
(check-exn exn:fail:schema? (lambda () (make-interface #:resources (list raw-resource))))
(check-exn exn:fail:schema?
  (lambda () (make-runtime (interface-descriptor #f '() (list raw-resource) '() '()))))
(define good-tool (make-tool "raw" '() values))
(for ([bad-tool (in-list (list (struct-copy tool-descriptor good-tool [input-schema invalid])
                              (struct-copy tool-descriptor good-tool [output-schema invalid])))])
  (check-exn exn:fail:schema? (lambda () (make-interface #:tools (list bad-tool)))))
;; An expression whose printed head is quote can be a user macro, not a literal.
(check-not-exn
 (lambda () (expand #'(module quoted-host mcp/lang
                       (require (for-syntax racket/base))
                       (define-syntax quote (syntax-rules () [(_ ignored) #hasheq((type . "string"))]))
                       (schema HostSchema (quote ignored))
                       (tool (accept [x (quote ignored)]) (text-result x))))))
