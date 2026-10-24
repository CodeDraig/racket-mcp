#lang racket/base
(require racket/list "../uri-template.rkt" "composition-literal.rkt")
(provide check-composed-manifest)
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
         (define references (hash-ref entry 'resource-references '()))
         (define prompt? (eq? (hash-ref target 'kind #f) 'prompt))
         (define reference? (if prompt? (hash-has-key? entry 'prompt-reference) (pair? references)))
         (define reference
           (if prompt? (hash-ref entry 'prompt-reference #f)
               (and (= (length references) 1) (car references))))
         (define local-target (and reference (hash-ref reference 'local-target #f)))
         (define resolved
           (and local-target
                (findf (lambda (candidate)
                         (and (eq? (hash-ref candidate 'kind) (hash-ref target 'kind #f))
                              (equal? (hash-ref candidate 'local-id #f) local-target))) entries)))
         ;; An unresolved lexical reference must not fall back to another
         ;; declaration sharing its name. The post-resolution pass checks it.
         (if reference?
             (and resolved
                  (let ([identity
                         (if prompt? (wire-name (hash-ref resolved 'name))
                             (let ([uri (hash-ref (hash-ref resolved 'metadata) 'uri)])
                               (and (hash-ref uri 'known? #f) (hash-ref uri 'value))))])
                    (and identity (list kind (hash-ref resolved 'kind) identity (hash-ref entry 'argument)))))
         (and (hash-ref target 'known? #f)
              (= 1 (count (lambda (candidate)
                            (and (eq? (hash-ref candidate 'kind) (hash-ref target 'kind))
                                 (equal? (wire-name (hash-ref candidate 'name)) (wire-name (hash-ref target 'name))))) entries))
              (list kind (hash-ref target 'kind) (wire-name (hash-ref target 'name)) (hash-ref entry 'argument))))]
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
