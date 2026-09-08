#lang racket/base
(require rackunit racket/match mcp
         (for-syntax racket/base racket/syntax syntax/parse mcp/extension))

(module extensions racket/base
  (require mcp (for-syntax racket/base racket/syntax syntax/parse mcp/extension))
  (provide assert-effect host-effect write)
  (begin-for-syntax
    (define (assert-visible context id expected)
      (define found (lookup-mcp-binding id #:space 'effect))
      (unless (eq? (and found #t) expected)
        (raise-syntax-error 'assert-effect "incorrect effect visibility" context id))
      (when found
        (require-mcp-binding id '(effect) #:space 'effect #:context context))))
  (define-syntax host-effect
    (syntax-parser
      [(_ adapter:id expected:boolean)
       (assert-visible this-syntax #'adapter (syntax-e #'expected))
       #'#t]))
  (define-mcp-extension assert-effect #:workflow
    (syntax-parser
      [(_ target:id adapter:id expected:boolean)
       (assert-visible this-syntax #'adapter (syntax-e #'expected))
       (when (lookup-mcp-binding ((make-syntax-introducer) #'adapter) #:space 'effect)
         (raise-syntax-error 'assert-effect "unrelated pending scope acquired effect" this-syntax #'adapter))
       #'(checkpoint [target Boolean] (host-effect adapter expected))]))
  (define-mcp-extension write #:workflow
    (syntax-parser
      [(_ target:id adapter:id value:expr)
       #'(perform [target Any] #:adapter adapter #:policy idempotent
           (begin (host-effect adapter #t) value))])))
(require (rename-in (submod "." extensions) [assert-effect scope] [write save]))

;; Stage extension checks and later ordinary host expansion must agree, including
;; preceding adapters across control-flow joins and separate value/effect spaces.
(workflow (visibility [writer String]) #:version "1"
  (scope before writer #f)
  (checkpoint [before-host Boolean] (host-effect writer #f))
  (save saved writer writer)
  (scope after writer #t)
  (checkpoint [host-shadow Boolean]
    (let ([writer "ordinary host value"]) (host-effect writer #f)))
  (let ([writer "local value"])
    (scope inherited writer #t)
    (save inner block-writer writer)
    (scope local block-writer #t)
    (text-result inner))
  (scope escaped-block block-writer #f)
  (scope inherited-join writer #t)
  (if #t
      (begin
        (scope yes-inherited writer #t)
        (save yes branch-writer "yes")
        (scope yes-local branch-writer #t)
        (text-result yes))
      (begin
        (scope no-sibling branch-writer #f)
        (scope no-inherited writer #t)
        (text-result "no")))
  (scope escaped-branch branch-writer #f)
  (match "case"
    [value
     (scope match-inherited writer #t)
     (save matched match-writer value)
     (scope match-local match-writer #t)
     (text-result matched)])
  (scope escaped-match match-writer #f)
  (scope final-inherited writer #t)
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Continue" 'requestedSchema (object-schema (hasheq))))
  (scope after-input writer #t)
  (text-result saved))

;; An extension-private adapter must not capture a same-spelled caller name.
(define-mcp-extension private-save #:workflow
  (syntax-parser
    [(_ target:id) #'(perform [target Any] #:adapter hidden #:policy idempotent "private")]))
(workflow (private) #:version "1"
  (private-save saved)
  (scope hidden-check hidden #f)
  (text-result saved))

;; No effect context leaks between workflows or outside workflow expansion.
(workflow (separate) #:version "1"
  (scope absent writer #f)
  (text-result "separate"))
(check-true (host-effect writer #f))
(define calls '())
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:tools (list visibility private separate)) #:store store
  #:adapters (for/hasheq ([name '(writer block-writer branch-writer match-writer hidden)])
    (values name (effect-adapter 'idempotent
      (lambda (value _key _transaction) (set! calls (cons name calls)) value))))))
(dynamic-wind void
  (lambda ()
    (define params (hasheq '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq)))
                           'name "visibility" 'arguments (hasheq 'writer "outer")))
    (define pending (dispatch rt "tools/call" params))
    (check-equal? (hash-count (hash-ref pending 'inputRequests)) 1)
    (define input-id (car (hash-keys (hash-ref pending 'inputRequests))))
    (check-equal? (reverse calls) '(writer block-writer branch-writer match-writer))
    (define retry (hash-set* params 'requestState (hash-ref pending 'requestState)
                            'inputResponses (hasheq input-id (hasheq 'action "decline"))))
    (check-equal? (dispatch rt "tools/call" retry) (text-result "outer"))
    (check-equal? (dispatch rt "tools/call" retry) (text-result "outer"))
    (check-equal? (length calls) 4)
    (check-equal? (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "private"))
                  (text-result "private"))
    (check-equal? (car calls) 'hidden)
    (check-equal? (dispatch rt "tools/call" (hasheq '_meta (request-meta) 'name "separate"))
                  (text-result "separate")))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))

(define-mcp-extension require-effect #:workflow
  (syntax-parser
    [(_ adapter:id)
     (require-mcp-binding #'adapter '(effect) #:space 'effect #:context this-syntax)
     #'(text-result "known")]))
(check-exn #rx"expected MCP effect binding"
  (lambda () (expand #'(workflow (forward) #:version "1"
                        (require-effect future)
                        (perform [saved Any] #:adapter future #:policy idempotent "x")
                        (text-result saved)))))

(module shifted racket/base
  (require (for-syntax racket/base mcp (rename-in (submod ".." extensions) [write save])))
  (provide baked)
  (begin-for-syntax
    (workflow (phase-effect) #:version "1"
      (assert-effect before adapter #f)
      (save saved adapter "phase")
      (assert-effect after adapter #t)
      (text-result saved)))
  (define-syntax (emit stx) #`'#,(tool-descriptor-name phase-effect))
  (define baked (emit)))
(require (submod "." shifted))
(check-equal? baked "phase-effect")
