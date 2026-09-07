#lang racket/base
(require rackunit mcp/uri-template)
(define (overlap a b) (uri-matchers-overlap (uri-template-matcher a) (uri-template-matcher b)))
(for ([pair '(("doc:///{id}" "doc:///fixed")
              ("doc:///{id}" "doc:///{other}")
              ("doc:///{a}/fixed" "doc:///fixed/{b}")
              ("doc:///{a}suffix" "doc:///prefix{b}")
              ("{a}%C3%A9/{b}" "{c}/{d}")
              ("doc:///{a}" "doc:///%C3%A9")
              ("doc:///{a}" "doc:///%c3%a9"))])
  (define a (uri-template-matcher (car pair)))
  (define b (uri-template-matcher (cadr pair)))
  (define uri (uri-matchers-overlap a b))
  (check-true (string? uri))
  (check-not-false (a uri))
  (check-not-false (b uri)))
(for ([pair '(("doc:///{id}" "other:///{id}")
              ("doc:///{id}" "doc:///path/two")
              ("{a}" "%FF") ("{a}" "%C0%80") ("{a}" "%ED%A0%80")
              ("{a}" "%F4%90%80%80") ("{a}" "%C3")
              ("{a}%C3/{b}" "{c}/{d}")
              ("doc:///{id}" "doc:///a+b"))])
  (check-false (apply overlap pair)))
(check-equal? (overlap "" "") "")
(check-equal? (overlap "{a}" "") "")
(check-equal? (uri-matchers-overlap (lambda (_) (error 'custom "must not invoke")) (uri-template-matcher "fixed")) 'unknown)
(check-exn #rx"state limit" (lambda () (uri-matchers-overlap (uri-template-matcher "long") (uri-template-matcher "long") #:max-states 1)))

(require mcp)
(define template (make-resource "template" "doc:///{id}" values #:arguments (list (argument 'id String #f #f))))
(define fixed (make-resource "fixed" "doc:///fixed" values))
(check-exn #rx"overlapping resource URI routes"
  (lambda () (make-interface #:resources (list template fixed))))
(check-exn #rx"overlapping resource URI routes"
  (lambda () (mount-interfaces (make-interface #:resources (list template)) (make-interface #:resources (list fixed)))))
(define separate (make-interface #:resources (list template (make-resource "other" "other:///fixed" values))))
(check-exn #rx"overlapping resource URI routes"
  (lambda () (view separate #:uris (hash "other:///fixed" "doc:///fixed"))))
(check-exn
 (lambda (e) (and (exn:fail:syntax? e) (regexp-match? #rx"overlapping resource URI routes" (exn-message e))
                  (for/or ([source (in-list (exn:fail:syntax-exprs e))])
                    (equal? (syntax-e source) "doc:///fixed"))))
 (lambda () (expand #'(module ambiguous mcp/lang
                       (resource (template [id String]) #:uri "doc:///{id}" id)
                       (resource (fixed) #:uri "doc:///fixed" "fixed")))))
(define custom-calls 0)
(define custom (make-resource "custom" "custom:///" values
                #:matcher (lambda (uri) (set! custom-calls (add1 custom-calls))
                            (and (equal? uri "doc:///fixed") (hasheq)))))
(define custom-interface (make-interface #:resources (list fixed custom)))
(check-equal? custom-calls 0)
(define rt (make-runtime custom-interface))
(check-equal? custom-calls 0)
(check-exn #rx"ambiguous resource URI"
 (lambda () (dispatch rt "resources/read" (hasheq '_meta (request-meta) 'uri "doc:///fixed"))))
(custodian-shutdown-all (runtime-custodian rt))
;; UTF-8 boundary code points remain in both the procedural and symbolic matcher.
(for ([point '(0 127 128 2047 2048 55295 57344 65535 65536 1114111)])
  (define uri (uri-template-expand "{x}" (hasheq 'x (string (integer->char point)))))
  (check-equal? (overlap "{x}" uri) uri))

;; Bounded independent enumeration catches missed overlaps in small languages.
;; Every symbolic witness must also be accepted by both procedural matchers.
(define templates '("" "a" "b" "/" "{x}" "a{x}" "{x}b" "{x}/{y}" "a/{x}" "{x}/b" "%FF" "%C3%A9"))
(define tokens '("a" "b" "/" "%00" "%FF" "%C3" "%A9"))
(define words
  (append '("") tokens
          (for*/list ([a (in-list tokens)] [b (in-list tokens)]) (string-append a b))))
(for* ([left (in-list templates)] [right (in-list templates)])
  (define a (uri-template-matcher left))
  (define b (uri-template-matcher right))
  (define witness (uri-matchers-overlap a b))
  (check-true
   (if (string? witness) (and (a witness) (b witness) #t)
       (not (for/or ([word (in-list words)]) (and (a word) (b word)))))
   (format "intersection of ~s and ~s" left right)))
