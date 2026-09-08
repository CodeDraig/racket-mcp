#lang racket/base
(require rackunit mcp
         (rename-in "../examples/extensions/checkpoint-copy.rkt" [checkpoint-copy copy])
         (for-syntax racket/base racket/syntax syntax/parse mcp/extension))

(define-syntax (host-only stx)
  (syntax-parse stx
    [(_ source:id)
     (when (lookup-mcp-binding #'source)
       (raise-syntax-error 'host-only "host binding incorrectly classified" stx #'source))
     #'#t]))
(define-mcp-extension checked-copy #:workflow
  (syntax-parser
    [(_ target:id source:id)
     (require-mcp-binding #'source '(workflow-value) #:context this-syntax)
     ;; A fresh unrelated scope cannot acquire the pending workflow binding.
     (when (lookup-mcp-binding ((make-syntax-introducer) #'source))
       (raise-syntax-error 'checked-copy "scope collision" this-syntax))
     ;; A real host binder introduced while an extension runs shadows the value.
     (local-expand #'(let ([source "host"]) (host-only source)) 'expression '())
     #'(copy [target String] source)]))
(define-mcp-extension absent #:workflow
  (syntax-parser
    [(_ source:id)
     (when (lookup-mcp-binding #'source)
       (raise-syntax-error 'absent "out-of-scope workflow value" this-syntax #'source))
     (with-syntax ([proof (car (generate-temporaries #'(proof)))])
       #'(checkpoint [proof Boolean] #t))]))

(workflow (visibility [name String]) #:version "1"
  (absent future)
  (checked-copy first name)
  (copy [second String] first)
  (let ([name "inner"])
    (checked-copy inner name)
    (text-result inner))
  (absent inner)
  (if #t
      (begin (checked-copy yes second) (text-result yes))
      (begin (absent yes) (checked-copy no first) (text-result no)))
  (absent yes)
  (checkpoint [future String] "later")
  (checked-copy final second)
  (text-result final))
(void (host-only name) (host-only final))

(schema Label String)
(workflow (shadow [Label String]) #:version "1"
  (copy [saved String] Label)
  (text-result saved))

(define-mcp-extension input-pair #:workflow
  (syntax-parser
    [(_ first:id second:id)
     #'(await-input ([first Any (hasheq 'mode "form" 'message "First" 'requestedSchema (object-schema (hasheq)))]
                     [second Any (hasheq 'mode "form" 'message "Second" 'requestedSchema (object-schema (hasheq)))]))]))
(define-mcp-extension write-value #:workflow
  (syntax-parser
    [(_ target:id source:id)
     (require-mcp-binding #'source '(workflow-value) #:context this-syntax)
     #'(perform [target Any] #:adapter writer #:policy idempotent source)]))
(workflow (input-effect) #:version "1"
  (input-pair first second)
  (copy [saved Any] first)
  (write-value written saved)
  (copy [finished Any] written)
  (structured-result (list finished second)))

(define store (open-memory-store))
(define effects 0)
(define rt (make-runtime (make-interface #:tools (list visibility shadow input-effect)) #:store store
  #:adapters (hasheq 'writer (effect-adapter 'idempotent
    (lambda (value _key _transaction) (set! effects (add1 effects)) value)))))
(dynamic-wind void
  (lambda ()
    (define result (dispatch rt "tools/call"
      (hasheq '_meta (request-meta) 'name "visibility" 'arguments (hasheq 'name "outer"))))
    (check-equal? result (text-result "outer"))
    (check-equal? (dispatch rt "tools/call"
      (hasheq '_meta (request-meta) 'name "shadow" 'arguments (hasheq 'Label "value")))
      (text-result "value"))
    (check-true (valid? Label "schema remains visible outside workflow"))
    (define params (hasheq '_meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))) 'name "input-effect"))
    (define pending (dispatch rt "tools/call" params))
    (check-equal? (sort (hash-keys (hash-ref pending 'inputRequests)) symbol<?) '(first second))
    (define resumed (hash-set* params 'requestState (hash-ref pending 'requestState)
      'inputResponses (hasheq 'first (hasheq 'action "decline") 'second (hasheq 'action "cancel"))))
    (define done (dispatch rt "tools/call" resumed))
    (check-equal? (hash-ref done 'structuredContent) (list (hasheq 'action "decline") (hasheq 'action "cancel")))
    (check-equal? (dispatch rt "tools/call" resumed) done)
    (check-equal? effects 1))
  (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))

;; A binding from a different workflow cannot leak into later expansion.
(check-exn #rx"expected MCP workflow-value binding"
  (lambda () (expand #'(workflow (unknown) #:version "1"
                        (copy [bad String] name) (text-result bad)))))

(module shifted racket/base
  (require (for-syntax racket/base mcp "../examples/extensions/checkpoint-copy.rkt"))
  (provide baked)
  (begin-for-syntax
    (workflow (phase-copy [name String]) #:version "1"
      (checkpoint-copy [saved String] name)
      (text-result saved)))
  (define-syntax (emit stx) #`'#,(tool-descriptor-name phase-copy))
  (define baked (emit)))
(require (submod "." shifted))
(check-equal? baked "phase-copy")
