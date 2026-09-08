#lang racket/base
(require rackunit racket/list mcp/private/manifest-diff)
(define (resource name uri [id #f])
  (define value (hasheq 'kind 'resource 'name name 'metadata (hasheq 'uri (hasheq 'known? #t 'value uri))))
  (if id (hash-set value 'local-id id) value))
(define first (resource 'document "first:///" "first"))
(define second (resource 'document "second:///" "second"))
(define (changes before after) (sort (map (lambda (entry) (hash-ref entry 'change)) (manifest-diff before after)) string<?))
(test-case "distinct resource URIs may share a display name"
  (check-equal? (changes (list first second) (list second first)) '("static-manifest-unchanged" "static-manifest-unchanged")))
(test-case "renaming a resource does not remove its URI"
  (check-equal? (changes (list first) (list (hash-set first 'name 'renamed))) '("review-required")))
(test-case "removing one same-named URI preserves the other"
  (check-equal? (changes (list first second) (list second)) '("breaking-removal" "static-manifest-unchanged")))
(test-case "duplicate URI identities are invalid even under different names"
  (check-exn #rx"duplicate declaration identity"
    (lambda () (manifest-diff (list first (resource 'renamed "first:///" "third")) '()))))
(test-case "unique declaration names still associate a URI replacement"
  (check-equal? (changes (list first) (list second)) '("breaking-contract-change")))
(test-case "retargeting a reference between same-named resources requires review"
  (define (tool target) (hasheq 'kind 'tool 'name 'read 'resource-references (list (hasheq 'name 'document 'local-target target))))
  (check-equal? (changes (list first second (tool "first")) (list first second (tool "second")))
                '("review-required" "static-manifest-unchanged" "static-manifest-unchanged")))
(define unknown (hash-set first 'metadata (hasheq 'uri (hasheq 'known? #f 'expression "runtime-uri"))))
(test-case "unresolved resource identities are reviewed, including repeated names"
  (check-equal? (changes (list (hash-remove unknown 'local-id) (hash-remove unknown 'local-id)) '())
                '("review-required" "review-required")))
(test-case "an unknown counterpart prevents a definite URI removal claim"
  (check-equal? (changes (list first) (list (hash-set unknown 'name 'other))) '("review-required" "review-required")))
(test-case "name alignment cannot hide a possibly retained URI"
  (check-equal? (changes (list first) (list second (hash-set unknown 'name 'other)))
                '("added" "review-required" "review-required")))
(define dynamic-mount (hasheq 'kind 'mount 'name 'computed))
(test-case "dynamic mounts may retain resources and operations"
  (check-equal? (changes (list first) (list second dynamic-mount))
                '("added" "review-required" "review-required"))
  (define tool (hasheq 'kind 'tool 'name 'read))
  (check-equal? (changes (list tool) (list dynamic-mount))
                '("review-required" "review-required"))
  (check-equal? (changes (list dynamic-mount) (list tool))
                '("review-required" "review-required")))
(test-case "definite URI losses hold for every completion of partial snapshots"
  ;; Independent finite oracle: substitute concrete URIs for unknowns, retaining
  ;; only worlds with unique published URIs. Display names impose no constraint.
  (define universe '("first:///" "second:///" "spare:///"))
  (define entries
    (for*/list ([name '(document other)] [uri '("first:///" "second:///" #f)])
      (if uri (resource name uri)
          (hash-set (hash-remove unknown 'local-id) 'name name))))
  (define (uri-of entry)
    (hash-ref (hash-ref (hash-ref entry 'metadata) 'uri) 'value #f))
  (define (worlds snapshot)
    (cond [(null? snapshot) '(())]
          [else
           (for*/list ([uri (if (uri-of (car snapshot)) (list (uri-of (car snapshot))) universe)]
                       [rest (worlds (cdr snapshot))] #:unless (member uri rest))
             (cons uri rest))]))
  (define snapshots
    (filter (lambda (snapshot) (pair? (worlds snapshot)))
            (append '(()) (map list entries)
                    (for*/list ([a entries] [b entries]) (list a b)))))
  (for* ([before snapshots] [after snapshots])
    (define reports (manifest-diff before after))
    (for* ([entry before] #:when (uri-of entry)
           [report reports]
           #:when (and (equal? (hash-ref report 'declaration)
                              (format "~a" (list 'resource (uri-of entry))))
                       (member (hash-ref report 'change)
                               '("breaking-removal" "breaking-contract-change"))))
      (for ([world (worlds after)])
        (check-false (member (uri-of entry) world)
                     (format "before ~s; after ~s; possible world ~s" before after world))))))
