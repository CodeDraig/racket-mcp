#lang racket/base
(require racket/list racket/string)
(provide manifest->mermaid)
;; User-supplied names are labels, never Mermaid identifiers or statements.
;; Mermaid's decimal entity syntax protects delimiters inside quoted labels.
(define (label value)
  (apply string-append
         (for/list ([ch (in-string (format "~a" value))])
           (cond [(or (char-alphabetic? ch) (char-numeric? ch)
                      (memv ch '(#\space #\- #\_ #\/ #\. #\:))) (string ch)]
                 [(char-whitespace? ch) " "]
                 [else (format "#~a;" (char->integer ch))]))))
(define (manifest->mermaid manifest)
  (unless (and (list? manifest) (andmap hash? manifest))
    (raise-argument-error 'manifest->mermaid "(listof hash?)" manifest))
  (define out (open-output-string))
  (define (node id text) (fprintf out "  ~a[\"~a\"]\n" id (label text)))
  (define (edge from to [text #f] [dotted? #f])
    (fprintf out "  ~a ~a~a ~a\n" from (if dotted? "-.->" "-->")
             (if text (format "|~a|" (label text)) "") to))
  (define declarations (for/list ([d (in-list manifest)] [i (in-naturals)]) (cons (format "d~a" i) d)))
  (define external (make-hash))
  (define (resource-target ref)
    (define candidates
      (filter (lambda (pair)
                (define d (cdr pair))
                (and (eq? (hash-ref d 'kind #f) 'resource)
                     (if (hash-has-key? ref 'local-target)
                         (and (hash-ref ref 'local-target)
                              (equal? (hash-ref d 'local-id #f) (hash-ref ref 'local-target)))
                         ;; Older manifests have only source/name hints.
                         (and (equal? (hash-ref d 'name #f) (hash-ref ref 'name #f))
                              (hash-ref ref 'source #f)
                              (equal? (hash-ref d 'source #f) (hash-ref ref 'source)))))) declarations))
    (cond [(= (length candidates) 1) (caar candidates)]
          [else
           (hash-ref! external ref
             (lambda ()
               (define id (format "r~a" (hash-count external)))
               (node id (format "~a resource: ~a"
                                (if (null? candidates) "external or unresolved" "ambiguous")
                                (hash-ref ref 'name "unknown")))
               id))]))
  (display "flowchart LR\n" out)
  (node "interface" "Interface")
  (for ([pair (in-list declarations)])
    (define id (car pair)) (define d (cdr pair))
    (node id (format "~a: ~a" (if (eq? (hash-ref d 'kind) 'mount) "dynamic mount" (hash-ref d 'kind)) (hash-ref d 'name)))
    (edge "interface" id))
  (for ([pair (in-list declarations)])
    (define id (car pair)) (define d (cdr pair))
    (for ([ref (in-list (hash-ref d 'resource-references '()))])
      (edge id (resource-target ref) "references" #t))
    (define stages (hash-ref d 'workflow-stages '()))
    (define stage-ids
      (for/hash ([stage (in-list stages)] [i (in-naturals)])
        (values (hash-ref stage 'id) (format "~a_s~a" id i))))
    (unless (= (hash-count stage-ids) (length stages))
      (error 'manifest->mermaid "duplicate workflow stage identity in ~a" (hash-ref d 'name)))
    (define (target key)
      (hash-ref stage-ids key (lambda () (error 'manifest->mermaid "unresolved workflow target ~a in ~a" key (hash-ref d 'name)))))
    (define adapters (make-hash))
    (unless (null? stages) (edge id (target (hash-ref (car stages) 'id)) "start" #t))
    (for ([stage (in-list stages)] [i (in-naturals)])
      (define sid (target (hash-ref stage 'id)))
      (define kind (hash-ref stage 'kind))
      (node sid (format "~a: ~a" kind (hash-ref stage 'id)))
      (case kind
        [(branch)
         (for ([destination (in-list (hash-ref stage 'adapter-or-targets))] [choice (in-naturals)])
           (edge sid (target destination) (format "branch ~a" choice)))]
        [(jump) (edge sid (target (hash-ref stage 'adapter-or-targets)) "join")]
        [(complete) (void)]
        [else (when (< (add1 i) (length stages))
                (edge sid (target (hash-ref (list-ref stages (add1 i)) 'id))))])
      (when (eq? kind 'effect)
        (define adapter (hash-ref stage 'adapter-or-targets))
        (define aid
          (hash-ref! adapters adapter
            (lambda ()
              (define aid (format "~a_a~a" id (hash-count adapters)))
              (node aid (format "adapter: ~a" adapter)) aid)))
        (edge sid aid (hash-ref stage 'policy "effect") #t))))
  (get-output-string out))
