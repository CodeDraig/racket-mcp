#lang racket/base

(provide resolve-mounted-references)
(define (resolve-mounted-references entries #:exclusions [exclusions '()])
  (define resources (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'resource)) entries))
  (define prompts (filter (lambda (entry) (eq? (hash-ref entry 'kind) 'prompt)) entries))
  (define dynamic? (ormap (lambda (entry) (eq? (hash-ref entry 'kind) 'mount)) entries))
  ;; Source hints are diagnostic data, not proof of binding identity. References
  ;; without a binding key remain unresolved across module boundaries.
  (define (same-binding? origin reference)
    (and origin (hash-ref origin 'binding-name #f) (hash-ref origin 'binding-provider #f)
         (equal? (hash-ref origin 'binding-name) (hash-ref reference 'binding-name #f))
         (equal? (hash-ref origin 'binding-provider) (hash-ref reference 'binding-provider #f))))
  (define (source-error entry message)
    (raise-syntax-error 'mount message
      (datum->syntax #f (hash-ref entry 'name)
        (map (lambda (field) (hash-ref entry field #f)) '(source line column position span)))))
  (for/list ([entry (in-list entries)])
    (define resource-resolved
     (if (hash-has-key? entry 'resource-references)
        (hash-set entry 'resource-references
          (for/list ([ref (in-list (hash-ref entry 'resource-references))])
            (define candidates
              (filter (lambda (resource) (same-binding? (hash-ref resource 'binding-origin #f) ref)) resources))
            (when (> (length candidates) 1)
              (source-error entry (format "references an ambiguous mounted resource: ~a" (hash-ref ref 'name))))
            (when (and (null? candidates) (not dynamic?)
                       (ormap (lambda (excluded) (and (eq? (hash-ref excluded 'kind 'resource) 'resource)
                                                      (same-binding? (hash-ref excluded 'binding-origin #f) ref))) exclusions))
              (source-error entry (format "references a resource removed by a composed view: ~a" (hash-ref ref 'name))))
            (if (and (not (hash-ref ref 'local-target #f)) (= (length candidates) 1))
                (hash-set ref 'local-target (hash-ref (car candidates) 'local-id)) ref))) entry))
    (define ref (hash-ref entry 'prompt-reference #f))
    (cond [ref
           (define candidates (filter (lambda (prompt) (same-binding? (hash-ref prompt 'binding-origin #f) ref)) prompts))
           (when (> (length candidates) 1)
             (source-error entry (format "references an ambiguous mounted prompt: ~a" (hash-ref ref 'name))))
           (when (and (null? candidates) (not dynamic?)
                      (ormap (lambda (excluded) (and (eq? (hash-ref excluded 'kind 'resource) 'prompt)
                                                     (same-binding? (hash-ref excluded 'binding-origin #f) ref))) exclusions))
             (source-error entry (format "references a prompt removed by a composed view: ~a" (hash-ref ref 'name))))
           (if (= (length candidates) 1)
               (hash-set* resource-resolved
                 'prompt-reference (hash-set ref 'local-target (hash-ref (car candidates) 'local-id))
                 'target (hash-set (hash-ref entry 'target) 'name (hash-ref (car candidates) 'name)))
               resource-resolved)]
          [else resource-resolved])))
