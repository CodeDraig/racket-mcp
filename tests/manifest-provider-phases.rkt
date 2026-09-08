#lang racket/base
(require rackunit racket/list racket/runtime-path mcp/private/manifest-diff)
(module provider racket/base
  (require mcp (for-syntax racket/base mcp))
  (provide document)
  (resource (document [id String]) #:uri "zero:///{id}" (error 'test "reader must not run"))
  (begin-for-syntax
    (provide document)
    (resource (document [id String]) #:uri "one:///{id}" (error 'test "reader must not run")))
  (error 'provider "manifest inspection must not instantiate the provider"))
(module app mcp/lang
  (require (only-in (submod ".." provider) [document ordinary])
           (for-meta -1 (only-in (submod ".." provider) [document shifted])))
  (tool (read-both [id String])
    (text-result (string-append (resource-uri (ordinary id))
                               (resource-uri (shifted id)))))
  (error 'app "manifest inspection must not instantiate the application"))
(define-runtime-path self "manifest-provider-phases.rkt")
(define manifest (dynamic-require `(submod ,self app manifest) 'manifest))
(define tool (car manifest))
(define references (hash-ref tool 'resource-references))
(test-case "provider phases distinguish same-named resource definitions"
  (check-equal? (length references) 2)
  (define providers (map (lambda (ref) (hash-ref ref 'binding-provider)) references))
  (check-equal? (length (remove-duplicates (map (lambda (p) (hash-ref p 'module)) providers))) 1)
  (check-equal? (map (lambda (p) (hash-ref p 'submodules)) providers) '(("provider") ("provider")))
  (check-equal? (sort (map (lambda (p) (hash-ref p 'phase)) providers) <) '(0 1)))
(test-case "removing either provider phase is a reviewable interface change"
  (for ([reference (in-list references)])
    (define reduced (list (hash-set tool 'resource-references (list reference))))
    (check-equal? (hash-ref (car (manifest-diff manifest reduced)) 'change) "review-required")))
