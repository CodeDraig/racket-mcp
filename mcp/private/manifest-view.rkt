#lang racket/base
(require "../uri-template.rkt" "composition-literal.rkt")
(provide transform-view)
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
               #:when (and (memq (hash-ref entry 'kind) '(resource prompt)) (not (memq entry selected))))
           (record-exclusion
            (hasheq 'kind (hash-ref entry 'kind) 'binding-origin (hash-ref entry 'binding-origin #f)
                    'source (format "~a" (syntax-source source)) 'line (syntax-line source)
                    'column (syntax-column source) 'position (syntax-position source) 'span (syntax-span source))))
         (define present (map (lambda (entry) (hash-ref entry 'local-id #f)) resources))
         (define present-prompts
           (for/list ([entry selected] #:when (eq? (hash-ref entry 'kind) 'prompt)) (hash-ref entry 'local-id #f)))
         (for ([entry (in-list selected)])
           (define prompt-reference (hash-ref entry 'prompt-reference #f))
           (when (and prompt-reference (hash-ref prompt-reference 'local-target #f)
                      (not (member (hash-ref prompt-reference 'local-target) present-prompts)))
             (raise-syntax-error 'view "removed a referenced prompt" source))
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
