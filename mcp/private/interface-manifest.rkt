#lang racket/base
(require racket/list "interface-binding.rkt" "composition-literal.rkt" "manifest-view.rkt"
         "manifest-identities.rkt" "manifest-references.rkt")
(provide (struct-out mounted-node) mount-manifest check-composed-manifest resolve-mounted-references)

(struct mounted-node (expressions source view-id mount-id unconditional?) #:transparent)
(define (prefix-identities entries prefix)
  (for/list ([entry (in-list entries)])
    (define located
      (if (hash-has-key? entry 'local-id)
          (hash-set entry 'local-id (string-append prefix (hash-ref entry 'local-id))) entry))
    (define prompted
      (if (and (hash-ref located 'prompt-reference #f)
               (hash-ref (hash-ref located 'prompt-reference) 'local-target #f))
          (hash-set located 'prompt-reference
            (hash-set (hash-ref located 'prompt-reference) 'local-target
                      (string-append prefix (hash-ref (hash-ref located 'prompt-reference) 'local-target)))) located))
    (define named (if (eq? (hash-ref entry 'kind) 'mount)
                      (hash-set prompted 'name (string-append prefix (wire-name (hash-ref prompted 'name)))) prompted))
    (if (hash-has-key? named 'resource-references)
        (hash-set named 'resource-references
          (for/list ([ref (in-list (hash-ref named 'resource-references))])
            (if (hash-ref ref 'local-target #f)
                (hash-set ref 'local-target (string-append prefix (hash-ref ref 'local-target))) ref))) named)))
(define (dynamic-mount expression prefix)
  (list (hasheq 'kind 'mount 'name prefix 'known? #f 'dynamic-metadata #t
                'expression (format "~s" (syntax->datum expression))
                'source (format "~a" (syntax-source expression))
                'line (syntax-line expression))))
(define (mount-manifest node index #:record-exclusion [record-exclusion void])
  (define (resolve expression prefix)
    (define imported (lookup-interface-manifest expression))
    (define parts (syntax->list expression))
    (cond [imported
           (for-each record-exclusion (lookup-interface-exclusions expression))
           (prefix-identities
            (filter (lambda (entry) (memq (hash-ref entry 'kind) '(tool workflow resource prompt completion mount))) imported) prefix)]
          [(and parts (pair? parts) (identifier? (car parts))
                (free-identifier=? (car parts) (mounted-node-mount-id node)))
           (append-map (lambda (child i) (resolve child (format "~a~a/" prefix i))) (cdr parts) (range (length (cdr parts))))]
          [(and parts (>= (length parts) 2) (identifier? (car parts))
                (free-identifier=? (car parts) (mounted-node-view-id node)))
           (define options
             (let loop ([rest (cddr parts)] [options (hasheq)])
               (cond [(null? rest) options]
                     [(and (pair? (cdr rest)) (keyword? (syntax-e (car rest))))
                      (define key (syntax-e (car rest)))
                      (unless (memq key '(#:include #:exclude #:rename #:namespace #:uris #:require-scopes #:adapters #:allow-adapters))
                        (raise-syntax-error 'view "unknown option" expression (car rest)))
                      (when (hash-has-key? options key) (raise-syntax-error 'view "duplicate option" expression (car rest)))
                      (loop (cddr rest) (hash-set options key (cadr rest)))]
                     [else (raise-syntax-error 'view "expected keyword and option expression" expression (car rest))])))
           (or (transform-view (resolve (cadr parts) prefix) options expression record-exclusion) (dynamic-mount expression prefix))]
          [else (dynamic-mount expression prefix)]))
  (append-map (lambda (expression child)
                (define prefix (format "mount-~a-~a/" index child))
                (if (mounted-node-unconditional? node) (resolve expression prefix)
                    (dynamic-mount (mounted-node-source node) prefix)))
              (mounted-node-expressions node) (range (length (mounted-node-expressions node)))))
