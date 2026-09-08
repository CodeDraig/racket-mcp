#lang racket/base
(require rackunit racket/file racket/match racket/string mcp
         "../examples/extensions/checkpoint-copy.rkt"
         (for-syntax racket/base racket/syntax syntax/parse))
(define predicates 0) (define applications 0) (define allowed? #t)
(define (accept? value) (set! predicates (add1 predicates)) allowed?)
(define (transform value) (set! applications (add1 applications)) (map string-upcase value))
(define request (hasheq 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
(workflow (snapshot-match [items (array-schema String)]) #:version "1"
  (match items
    [(? accept? (app transform (list captured ...)))
     (checkpoint-copy [saved Any] captured)
     (await-input [answer Any] request)
     (checkpoint-copy [restored Any] captured)
     (structured-result (list saved restored))]
    [_ (text-result "other")]))
(define joined '())
(define (record value) (set! joined (cons value joined)) (text-result value))
(workflow (shadow [value String]) #:version "1"
  (match '("inner")
    [(list value) (checkpoint-copy [saved String] value) (record saved)])
  (text-result value))
(workflow (nested [items Any]) #:version "1"
  (match items
    [(list first (list second))
     (match (list second first)
       [(list first second)
        (checkpoint-copy [one String] first)
        (checkpoint-copy [two String] second)
        (structured-result (list one two))])]))

;; A private temporary introduced by a match expander is captured along with the
;; public variable, without guessing names or expanding that pattern twice.
(begin-for-syntax (define expansions 0))
(define-match-expander tagged
  (lambda (stx)
    (set! expansions (add1 expansions))
    (syntax-parse stx
      [(_ value:id)
       (with-syntax ([private (generate-temporary #'value)])
         #'(and (list "tag" value) (app values private)))])))
(workflow (expanded [items Any]) #:version "1"
  (match items
    [(tagged value) (checkpoint-copy [saved String] value) (text-result saved)]))
(define-syntax (expansion-count stx) #`#,expansions)
(check-equal? (expansion-count) 1)

(module provider racket/base
  (require racket/match (for-syntax racket/base))
  (provide imported-tag)
  (define-match-expander imported-tag
    (syntax-rules () [(_ value) (list "imported" value)])))
(require (rename-in (submod "." provider) [imported-tag tag]))
(workflow (imported [items Any]) #:version "1"
  (match items [(tag value) (checkpoint-copy [saved String] value) (text-result saved)]))
(workflow (alternative [items Any]) #:version "1"
  (match items
    [(or (list "one" value) (list "two" value))
     (checkpoint-copy [saved String] value) (text-result saved)]
    [(list value value) (checkpoint-copy [saved String] value) (text-result saved)]))
(workflow (non-data [value String]) #:version "1"
  (match value [(app (lambda (v) (lambda () v)) callback) (text-result (callback))]))

(define path (make-temporary-file "mcp-match-~a.sqlite"))
(define store (open-sqlite-store path))
(define interface (make-interface #:tools (list snapshot-match shadow nested expanded imported alternative non-data)))
(define runtime (make-runtime interface #:store store))
(define (call name arguments [extra (hasheq)])
  (dispatch runtime "tools/call"
            (hash-set* extra '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq)))
                       'name name 'arguments arguments)))
(dynamic-wind void
  (lambda ()
    (define args (hasheq 'items '("first" "second")))
    (define first (call "snapshot-match" args))
    (check-equal? predicates 1) (check-equal? applications 1)
    (define retry (hasheq 'requestState (hash-ref first 'requestState)))
    (check-equal? (hash-ref (call "snapshot-match" args retry) 'inputRequests) (hash-ref first 'inputRequests))
    (check-equal? predicates 1) (check-equal? applications 1)
    ;; Matching now would choose the other branch. Resumption must use the
    ;; committed decision and the transformed values, including ellipsis lists.
    (set! allowed? #f)
    (custodian-shutdown-all (runtime-custodian runtime))
    (close-store! store)
    (set! store (open-sqlite-store path))
    (set! runtime (make-runtime interface #:store store))
    (define input (car (hash-keys (hash-ref first 'inputRequests))))
    (define done (call "snapshot-match" args (hash-set retry 'inputResponses (hasheq input (hasheq 'action "decline")))))
    (check-equal? (hash-ref done 'structuredContent) '(("FIRST" "SECOND") ("FIRST" "SECOND")))
    (check-equal? (call "snapshot-match" args retry) done)
    (check-equal? predicates 1) (check-equal? applications 1)
    (check-equal? (call "snapshot-match" args) (text-result "other"))
    (check-equal? predicates 2) (check-equal? applications 1)
    (check-equal? (call "shadow" (hasheq 'value "outer")) (text-result "outer"))
    (check-equal? joined '("inner"))
    (check-equal? (hash-ref (call "nested" (hasheq 'items '("A" ("B")))) 'structuredContent) '("B" "A"))
    (check-equal? (call "expanded" (hasheq 'items '("tag" "retained"))) (text-result "retained"))
    (check-equal? (call "imported" (hasheq 'items '("imported" "foreign"))) (text-result "foreign"))
    (check-equal? (call "alternative" (hasheq 'items '("one" "first"))) (text-result "first"))
    (check-equal? (call "alternative" (hasheq 'items '("two" "second"))) (text-result "second"))
    (check-equal? (call "alternative" (hasheq 'items '("equal" "equal"))) (text-result "equal"))
    (check-exn #rx"failed its codec schema" (lambda () (call "non-data" (hasheq 'value "closure")))))
  (lambda () (custodian-shutdown-all (runtime-custodian runtime)) (close-store! store) (delete-file path)))

(check-exn #rx"expected MCP workflow-value binding"
  (lambda ()
    (expand #'(workflow (out-of-scope) #:version "1"
                (match '("one") [(list captured) (text-result captured)])
                (checkpoint-copy [bad String] captured) (text-result bad)))))

(module shifted racket/base
  (require (for-syntax racket/base racket/match mcp "../examples/extensions/checkpoint-copy.rkt"))
  (provide baked)
  (begin-for-syntax
    (workflow (phase-match [items Any]) #:version "1"
      (match items [(list value) (checkpoint-copy [saved String] value) (text-result saved)]))
    (define state (open-memory-store))
    (define rt (make-runtime (make-interface #:tools (list phase-match)) #:store state))
    (define result
      (dynamic-wind void
        (lambda () (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "phase-match" 'arguments (hasheq 'items '("shifted")))))
        (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! state)))))
  (define-syntax (emit stx) #`'#,result)
  (define baked (emit)))
(require (submod "." shifted))
(check-equal? baked (text-result "shifted"))

;; Compiler temporaries must not make equal declarations get different workflow
;; fingerprints just because another module was expanded first.
(define-namespace-anchor home)
(parameterize ([current-namespace (namespace-anchor->namespace home)])
  (define fingerprints
    (for/list ([module-name '(match-fingerprint-one match-fingerprint-two)])
      (eval `(module ,module-name racket/base
               (require mcp racket/match)
               (provide operation)
               (workflow (operation [items Any]) #:version "1"
                 (match items [(list value) (text-result value)]))))
      (workflow-descriptor-fingerprint
       (tool-descriptor-workflow (dynamic-require `(quote ,module-name) 'operation)))))
  (check-equal? (car fingerprints) (cadr fingerprints)))
