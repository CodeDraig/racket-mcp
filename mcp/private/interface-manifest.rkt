#lang racket/base
(require racket/list syntax/parse "interface-binding.rkt" "../uri-template.rkt"
         (for-template racket/base))
(provide (struct-out mounted-node) mount-manifest check-composed-manifest resolve-mounted-references)
(struct mounted-node (expressions source view-id mount-id unconditional?) #:transparent)
(define unknown (gensym 'dynamic))
;; Interpret only this closed, binding-checked literal grammar. Never expand or
;; evaluate arbitrary Racket expressions to discover an interface or option.
(define (literal stx)
  (define datum (syntax->datum stx))
  (cond [(or (string? datum) (boolean? datum) (number? datum) (hash? datum)) datum]
        [else
         (syntax-parse stx #:literals (quote list hash hasheq hasheqv)
           [(quote datum) (syntax->datum #'datum)]
           [(list item ...)
            (define items (map literal (syntax->list #'(item ...))))
            (if (memq unknown items) unknown items)]
           [((~and constructor (~or hash hasheq hasheqv)) item ...)
            (define items (map literal (syntax->list #'(item ...))))
            (if (or (memq unknown items) (odd? (length items))) unknown
                (apply (cond [(free-identifier=? #'constructor #'hasheq) hasheq]
                             [(free-identifier=? #'constructor #'hasheqv) hasheqv] [else hash]) items))]
           [_ unknown])]))
(define (described stx)
  (define value (literal stx))
  (if (eq? value unknown) (hasheq 'known? #f 'expression (format "~s" (syntax->datum stx)))
      (hasheq 'known? #t 'value value)))
(define (wire-name name) (if (symbol? name) (symbol->string name) name))
(define (prefix-identities entries prefix)
  (for/list ([entry (in-list entries)])
    (define located
      (if (hash-has-key? entry 'local-id)
          (hash-set entry 'local-id (string-append prefix (hash-ref entry 'local-id))) entry))
    (define named (if (eq? (hash-ref entry 'kind) 'mount)
                      (hash-set located 'name (string-append prefix (wire-name (hash-ref located 'name)))) located))
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
(define (transform-view entries options source record-exclusion)
  (define (option keyword default) (if (hash-has-key? options keyword) (literal (hash-ref options keyword)) default))
  (define include (option '#:include #f))
  (define exclude (option '#:exclude '()))
  (define rename (option '#:rename (hash)))
  (define namespace (option '#:namespace ""))
  (define uris (option '#:uris (hash)))
  (define (strings? value) (and (list? value) (andmap string? value)))
  (define (string-map? value) (and (hash? value) (for/and ([(key val) (in-hash value)]) (and (string? key) (string? val)))))
  (define (check value predicate keyword)
    (unless (or (eq? value unknown) (predicate value))
      (raise-syntax-error 'view (format "invalid literal ~a option" keyword) source (hash-ref options keyword source))))
  (check include (lambda (v) (or (not v) (strings? v))) '#:include)
  (check exclude strings? '#:exclude)
  (check rename string-map? '#:rename)
  (check namespace string? '#:namespace)
  (check uris string-map? '#:uris)
  (and (not (memq unknown (list include exclude rename namespace uris)))
       ;; A dynamic child may publish identities affected by any transformation.
       (not (ormap (lambda (entry) (eq? (hash-ref entry 'kind) 'mount)) entries))
       (for/and ([entry (in-list entries)])
         (case (hash-ref entry 'kind)
           [(completion) (hash-ref (hash-ref entry 'target) 'known? #f)]
           [(resource) (or (zero? (hash-count uris)) (hash-ref (hash-ref (hash-ref entry 'metadata) 'uri) 'known? #f))]
           [else #t]))
       (let ()
         (define (keep? name) (and (or (not include) (member (wire-name name) include))
                                   (not (member (wire-name name) exclude))))
         (define (name old)
           (define new (string-append namespace (hash-ref rename (wire-name old) (wire-name old))))
           (if (symbol? old) (string->symbol new) new))
         (define selected
           (filter (lambda (entry)
                     (if (eq? (hash-ref entry 'kind) 'completion)
                         (keep? (hash-ref (hash-ref entry 'target) 'name))
                         (keep? (hash-ref entry 'name)))) entries))
         (define resources (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'resource)) selected))
         (for ([entry (in-list entries)]
               #:when (and (eq? (hash-ref entry 'kind) 'resource) (not (memq entry selected))))
           (record-exclusion
            (hasheq 'binding-origin (hash-ref entry 'binding-origin #f)
                    'source (format "~a" (syntax-source source)) 'line (syntax-line source)
                    'column (syntax-column source) 'position (syntax-position source) 'span (syntax-span source))))
         (define present (map (lambda (entry) (hash-ref entry 'local-id #f)) resources))
         (for ([entry (in-list selected)])
           (for ([ref (in-list (hash-ref entry 'resource-references '()))])
             (when (and (hash-ref ref 'local-target #f) (not (member (hash-ref ref 'local-target) present)))
               (raise-syntax-error 'view "removed a referenced resource" source))))
         (for/list ([entry (in-list selected)])
           (define kind (hash-ref entry 'kind))
           (define renamed (hash-set entry 'name (name (hash-ref entry 'name))))
           (define transformed
             (case kind
               [(completion) (hash-set renamed 'target (hash-set (hash-ref entry 'target) 'name (name (hash-ref (hash-ref entry 'target) 'name))))]
               [(resource)
                (define metadata (hash-ref entry 'metadata))
                (define uri-description (hash-ref metadata 'uri))
                (if (hash-ref uri-description 'known? #f)
                    (let* ([old (hash-ref uri-description 'value)] [new (hash-ref uris old old)])
                      (unless (equal? (sort (uri-template-variables old) symbol<?) (sort (uri-template-variables new) symbol<?))
                        (raise-syntax-error 'view "URI remapping must preserve template variables" source))
                      (define updated (hash-set metadata 'uri (hasheq 'known? #t 'value new)))
                      (hash-set renamed 'metadata
                        (if (equal? old new) updated (hash-set updated 'matcher (hasheq 'known? #t 'value #f))))) renamed)]
               [else renamed]))
           (define policies
             (for/hasheq ([(keyword value) (in-hash options)] #:when (memq keyword '(#:require-scopes #:adapters #:allow-adapters)))
               (values (string->symbol (keyword->string keyword)) (described value))))
           (if (zero? (hash-count policies)) transformed
               (hash-set* transformed 'composition-policies
                 (append (hash-ref transformed 'composition-policies '()) (list policies))
                 'dynamic-metadata
                 (or (hash-ref transformed 'dynamic-metadata #f)
                     (for/or ([policy (in-hash-values policies)]) (not (hash-ref policy 'known?))))))))))
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
(define (check-composed-manifest entries source)
  (define seen (make-hash))
  (define routes '())
  (for ([entry (in-list entries)])
    (define kind (hash-ref entry 'kind))
    (define key
      (case kind
        [(tool workflow) (list 'tool (wire-name (hash-ref entry 'name)))]
        [(prompt) (list kind (wire-name (hash-ref entry 'name)))]
        [(resource)
         (define uri (hash-ref (hash-ref entry 'metadata) 'uri))
         (and (hash-ref uri 'known? #f) (list kind (hash-ref uri 'value)))]
        [(completion)
         (define target (hash-ref entry 'target))
         (and (hash-ref target 'known? #f)
              (= 1 (count (lambda (candidate)
                            (and (eq? (hash-ref candidate 'kind) (hash-ref target 'kind))
                                 (equal? (wire-name (hash-ref candidate 'name)) (wire-name (hash-ref target 'name))))) entries))
              (list kind (hash-ref target 'kind) (wire-name (hash-ref target 'name)) (hash-ref entry 'argument)))]
        [else #f]))
    (when key
      (when (hash-has-key? seen key) (raise-syntax-error 'mount (format "duplicate statically known published identity: ~a" key) source))
      (hash-set! seen key #t))
    (when (eq? kind 'resource)
      (define metadata (hash-ref entry 'metadata))
      (define uri (hash-ref metadata 'uri))
      (define matcher (hash-ref metadata 'matcher (hasheq 'known? #t 'value #f)))
      (when (and (hash-ref uri 'known? #f) (hash-ref matcher 'known? #f) (not (hash-ref matcher 'value)))
        (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'mount (exn-message e) source))])
          (define route (uri-template-matcher (hash-ref uri 'value)))
          (for ([prior (in-list routes)])
            (define witness (uri-matchers-overlap route prior))
            (when (string? witness) (error 'mount "overlapping resource URI routes match ~s" witness)))
          (set! routes (cons route routes)))))))
(define (resolve-mounted-references entries #:exclusions [exclusions '()])
  (define resources (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'resource)) entries))
  (define dynamic? (ormap (lambda (entry) (eq? (hash-ref entry 'kind) 'mount)) entries))
  ;; Source hints are diagnostic data, not proof of binding identity. Older
  ;; manifests without a binding key remain unresolved across module boundaries.
  (define (same-binding? origin reference)
    (and origin (hash-ref origin 'binding-name #f) (hash-ref origin 'binding-provider #f)
         (equal? (hash-ref origin 'binding-name) (hash-ref reference 'binding-name #f))
         (equal? (hash-ref origin 'binding-provider) (hash-ref reference 'binding-provider #f))))
  (define (source-error entry message)
    (raise-syntax-error 'mount message
      (datum->syntax #f (hash-ref entry 'name)
        (map (lambda (field) (hash-ref entry field #f)) '(source line column position span)))))
  (for/list ([entry (in-list entries)])
    (if (hash-has-key? entry 'resource-references)
        (hash-set entry 'resource-references
          (for/list ([ref (in-list (hash-ref entry 'resource-references))])
            (define candidates
              (filter (lambda (resource) (same-binding? (hash-ref resource 'binding-origin #f) ref)) resources))
            (when (> (length candidates) 1)
              (source-error entry (format "references an ambiguous mounted resource: ~a" (hash-ref ref 'name))))
            (when (and (null? candidates) (not dynamic?)
                       (ormap (lambda (excluded) (same-binding? (hash-ref excluded 'binding-origin #f) ref)) exclusions))
              (source-error entry (format "references a resource removed by a composed view: ~a" (hash-ref ref 'name))))
            (if (and (not (hash-ref ref 'local-target #f)) (= (length candidates) 1))
                (hash-set ref 'local-target (hash-ref (car candidates) 'local-id)) ref))) entry)))
