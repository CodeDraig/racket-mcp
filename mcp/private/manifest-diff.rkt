#lang racket/base
(require racket/list)
(provide manifest-diff)
(define location-fields '(source line column position span))
(define (without value fields)
  (for/fold ([result value]) ([field (in-list fields)]) (hash-remove result field)))
(define (contract entry)
  ;; Strip compiler-owned locations only. A schema property called "source" or
  ;; "line" is application data and must still participate in comparison.
  (define stripped (without entry (cons 'local-id location-fields)))
  (define base
    (if (hash-ref stripped 'binding-origin #f)
        (hash-set stripped 'binding-origin (without (hash-ref stripped 'binding-origin) '(line column position span binding-name))) stripped))
  (define stages
    (if (hash-has-key? base 'workflow-stages)
        (hash-set base 'workflow-stages
                  (map (lambda (stage) (without stage location-fields)) (hash-ref base 'workflow-stages))) base))
  (if (hash-has-key? stages 'resource-references)
      (hash-set stages 'resource-references
                (remove-duplicates
                 (map (lambda (ref)
                        (define located (without ref '(line column position span local-target)))
                        (define stable (if (hash-ref ref 'local-target #f) (hash-remove located 'binding-name) located))
                        (if (hash-has-key? ref 'local-target)
                            (hash-set stable 'target-scope (if (hash-ref ref 'local-target) 'local 'external))
                            stable))
                      (hash-ref stages 'resource-references)) equal?)) stages))
(define (resource? entry) (and entry (eq? (hash-ref entry 'kind) 'resource)))
(define (resource-uri entry)
  (and (resource? entry)
       (let ([uri (hash-ref (hash-ref entry 'metadata (hasheq)) 'uri (hasheq))])
         (and (hash-ref uri 'known? #f) (string? (hash-ref uri 'value #f)) (hash-ref uri 'value)))))
(define (unknown-resource? entry) (and (resource? entry) (not (resource-uri entry))))
(define (dynamic-mount? entry) (and entry (eq? (hash-ref entry 'kind) 'mount)))
(define (completion-target entry)
  (define target (hash-ref entry 'target (hasheq)))
  (and (hash-ref target 'known? #f)
       (case (hash-ref target 'kind #f)
         [(prompt) (list 'prompt (hash-ref target 'name))]
         [(resource)
          (define references (hash-ref entry 'resource-references '()))
          (and (= (length references) 1)
               (let ([identity (hash-ref (car references) 'local-target-declaration #f)])
                 (and identity (string? (cadr identity)) identity)))]
         [else #f])))
(define (unknown-completion? entry)
  (and entry (eq? (hash-ref entry 'kind) 'completion) (not (completion-target entry))))
(define (key entry [ordinal 0])
  (define kind (hash-ref entry 'kind))
  (case kind
    [(server) '(server)]
    [(tool workflow) (list 'tool (hash-ref entry 'name))]
    [(resource) (list kind (or (resource-uri entry) (list 'unknown (hash-ref entry 'name) ordinal)))]
    [(completion) (list kind (or (completion-target entry) (list 'unknown ordinal)) (hash-ref entry 'argument))]
    [else (list kind (hash-ref entry 'name))]))
(define (index manifest)
  (unless (and (list? manifest) (andmap hash? manifest))
    (raise-argument-error 'manifest-diff "(listof hash?)" manifest))
  (define local-targets
    (for/fold ([targets (hash)]) ([entry (in-list manifest)] [ordinal (in-naturals)]
                                 #:when (and (eq? (hash-ref entry 'kind #f) 'resource)
                                             (hash-has-key? entry 'local-id)))
      (define id (hash-ref entry 'local-id))
      (when (hash-has-key? targets id)
        (error 'manifest-diff "duplicate local declaration identity: ~a" id))
      (hash-set targets id (key entry ordinal))))
  (for/fold ([result (hash)]) ([entry (in-list manifest)] [ordinal (in-naturals)])
    (define normalized
      (if (hash-has-key? entry 'resource-references)
          (hash-set entry 'resource-references
            (for/list ([ref (in-list (hash-ref entry 'resource-references))])
              (cond [(hash-ref ref 'local-target #f)
                     (hash-set ref 'local-target-declaration
                       (hash-ref local-targets (hash-ref ref 'local-target)
                         (lambda () (error 'manifest-diff "unresolved local resource target: ~a"
                                           (hash-ref ref 'local-target)))))]
                    [else (hash-remove ref 'local-target-declaration)])))
          entry))
    (define id (key normalized ordinal))
    (when (hash-has-key? result id) (error 'manifest-diff "duplicate declaration identity: ~a" id))
    (hash-set result id normalized)))
(define (workflow-version entry)
  (define metadata (hash-ref entry 'metadata (hasheq)))
  (hash-ref metadata (if (eq? (hash-ref entry 'kind) 'workflow) 'version 'workflow) (hasheq 'known? #f)))
(define (workflow-status old new)
  (cond [(and (not (hash-has-key? old 'workflow-stages)) (not (hash-has-key? new 'workflow-stages))) #f]
        [(not (hash-has-key? old 'workflow-stages)) "new-workflow"]
        [(not (hash-has-key? new 'workflow-stages)) "workflow-removed"]
        [else
         (define before (workflow-version old)) (define after (workflow-version new))
         (cond [(and (hash-ref before 'known? #f) (hash-ref after 'known? #f)
                     (not (equal? (hash-ref before 'value) (hash-ref after 'value)))) "incompatible-version"]
               [(not (equal? (hash-ref (contract old) 'workflow-stages) (hash-ref (contract new) 'workflow-stages))) "review-required"]
               [else "not-established-from-manifest"])]))
(define (breaking-reasons before after)
  (define (known-client-requirements entry)
    (define information (hash-ref entry 'client-capabilities #f))
    (and (hash? information)
         (eq? (hash-ref information 'analysis #f) 'declared-workflow-stages)
         (hash? (hash-ref information 'required #f))
         (hash-ref information 'required)))
  (define old-capabilities (known-client-requirements before))
  (define new-capabilities (known-client-requirements after))
  (define (present? object path)
    (or (null? path)
        (and (hash? object) (hash-has-key? object (car path))
             (present? (hash-ref object (car path)) (cdr path)))))
  (define capabilities
    (if (and old-capabilities new-capabilities)
        (for/list ([path '((elicitation) (extensions io.modelcontextprotocol/tasks))]
                   #:when (and (present? new-capabilities path) (not (present? old-capabilities path))))
          (format "Client capability ~a is newly required." path)) '()))
  (define arguments (hash-ref before 'arguments '()))
  (define required
    (if (and (hash-has-key? before 'arguments) (hash-has-key? after 'arguments))
        (for/list ([argument (in-list (hash-ref after 'arguments))]
                   #:when (and (eq? (hash-ref argument 'required #f) #t)
                               (let ([old (findf (lambda (old) (equal? (hash-ref argument 'name) (hash-ref old 'name))) arguments)])
                                 (or (not old)
                                     (and (hash-has-key? old 'required) (eq? (hash-ref old 'required) #f))))))
          (format "Argument ~a is newly required." (hash-ref argument 'name))) '()))
  (define old-uri (hash-ref (hash-ref before 'metadata (hasheq)) 'uri (hasheq 'known? #f)))
  (define new-uri (hash-ref (hash-ref after 'metadata (hasheq)) 'uri (hasheq 'known? #f)))
  (append required capabilities
          (if (and (eq? (hash-ref before 'kind) 'resource)
                   (hash-ref old-uri 'known? #f) (hash-ref new-uri 'known? #f)
                   (not (equal? (hash-ref old-uri 'value) (hash-ref new-uri 'value))))
              (list "The declared published resource URI or template changed.") '())))
;; URI identity takes precedence over display names. Associate unmatched entries
;; by a name only when it is unique on both sides, retaining the useful single
;; URI-replacement report without conflating same-named published resources.
(define (align-resources old new)
  ;; An unresolved URI could retain either unmatched identity. Display-name
  ;; pairing must not turn that uncertainty into a definite URI replacement.
  (define uncertain?
    (ormap (lambda (entry) (or (unknown-resource? entry) (dynamic-mount? entry)))
           (append (hash-values old) (hash-values new))))
  (define missing-old (for/list ([(id entry) (in-hash old)] #:when (and (resource? entry) (not (hash-has-key? new id)))) (cons id entry)))
  (define missing-new (for/list ([(id entry) (in-hash new)] #:when (and (resource? entry) (not (hash-has-key? old id)))) (cons id entry)))
  (define (same-name? a b) (equal? (hash-ref (cdr a) 'name) (hash-ref (cdr b) 'name)))
  (for/fold ([result new]) ([prior (in-list missing-old)])
    (define candidates (filter (lambda (next) (same-name? prior next)) missing-new))
    (if (and (not uncertain?) (= (length candidates) 1) (= (count (lambda (other) (same-name? prior other)) missing-old) 1))
        (hash-set (hash-remove result (caar candidates)) (car prior) (cdar candidates)) result)))
(define (manifest-diff before after)
  (define old (index before)) (define new (align-resources old (index after)))
  (define unknown-before? (ormap unknown-resource? (hash-values old)))
  (define unknown-after? (ormap unknown-resource? (hash-values new)))
  (define dynamic-before? (ormap dynamic-mount? (hash-values old)))
  (define dynamic-after? (ormap dynamic-mount? (hash-values new)))
  (define unknown-completions-before? (ormap unknown-completion? (hash-values old)))
  (define unknown-completions-after? (ormap unknown-completion? (hash-values new)))
  (define ids (sort (remove-duplicates (append (hash-keys old) (hash-keys new)) equal?) string<? #:key (lambda (id) (format "~s" id))))
  (for/list ([id (in-list ids)])
    (define prior (hash-ref old id #f)) (define next (hash-ref new id #f))
    (define base (hasheq 'declaration (format "~a" id) 'behavior "not-compared"))
    (cond [(or (unknown-completion? prior) (unknown-completion? next)
               (and (not next) prior (eq? (hash-ref prior 'kind) 'completion) unknown-completions-after?)
               (and (not prior) next (eq? (hash-ref next 'kind) 'completion) unknown-completions-before?))
           (hash-set* base 'change "review-required"
                      'reasons (list "An unresolved completion target prevents establishing the published identity change."))]
          [(or (dynamic-mount? prior) (dynamic-mount? next)
               (and (not next) dynamic-after?)
               (and (not prior) dynamic-before?))
           (hash-set* base 'change "review-required"
                      'reasons (list "The published surface of a dynamic mount is not established by the manifest."))]
          [(or (unknown-resource? prior) (unknown-resource? next)
               (and (not next) (resource? prior) unknown-after?)
               (and (not prior) (resource? next) unknown-before?))
           (hash-set* base 'change "review-required"
                      'reasons (list "An unresolved resource URI prevents establishing the published identity change."))]
          [(not next) (hash-set* base 'change "breaking-removal" 'reasons (list "The published declaration was removed."))]
          [(not prior) (hash-set* base 'change "added" 'reasons '())]
          [else
           (define a (contract prior)) (define b (contract next))
           (define fields (sort (remove-duplicates (append (hash-keys a) (hash-keys b))) symbol<?))
           (define (same? field)
             (and (hash-has-key? a field) (hash-has-key? b field) (equal? (hash-ref a field) (hash-ref b field))))
           (define changed (filter (lambda (field) (not (same? field))) fields))
           (define reasons (breaking-reasons prior next))
           (define result
             (hash-set* base 'change (cond [(pair? reasons) "breaking-contract-change"]
                                          [(null? changed) "static-manifest-unchanged"] [else "review-required"])
                        'changed-fields (map symbol->string changed)
                        'unchanged-fields (map symbol->string (filter same? fields))
                        'reasons reasons))
           (define workflow (workflow-status prior next))
           (if workflow (hash-set result 'workflow-compatibility workflow) result)])))
