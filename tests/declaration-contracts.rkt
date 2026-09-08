#lang racket/base
(require rackunit racket/file racket/runtime-path mcp mcp/completion)
(define calls 0)
(define (handler . _) (set! calls (add1 calls)) (text-result "ok"))
(define good-tool (make-tool "tool" '() handler))
(define good-resource (make-resource "resource" "test:///resource" handler))
(define good-prompt (make-prompt "prompt" '() handler))
(for ([construct (in-list
                  (list (lambda () (make-tool "tool" '() handler #:description 42))
                        (lambda () (make-resource "resource" "test:///resource" handler #:description 42))
                        (lambda () (make-prompt "prompt" '() handler #:description 42))
                        (lambda () (make-tool "tool" '() 42))
                        (lambda () (make-resource "resource" "test:///resource" 42))
                        (lambda () (make-prompt "prompt" '() 42))
                        (lambda () (make-tool "tool" '() (lambda () "wrong arity")))
                        (lambda () (make-resource "resource" "test:///{id}" (lambda () "wrong arity") #:arguments (list (argument 'id String #f #f))))
                        (lambda () (make-prompt "prompt" '() (lambda () "wrong arity")))
                        (lambda () (make-tool "tool" '() handler #:raw? 'yes))
                        (lambda () (make-tool "tool" '() handler #:annotations (hasheq 'readOnlyHint "yes")))
                        (lambda () (make-tool "tool" '() handler #:annotations (hasheq 'title 42)))
                        (lambda () (make-tool "tool" '() handler #:annotations (hasheq 'extra handler)))
                        (lambda () (make-resource "resource" "test:///resource" handler #:mime-type 42))
                        (lambda () (make-resource "resource" "test:///resource" handler #:matcher 42))
                        (lambda () (make-tool "tool" '() handler #:workflow 'invalid))
                        (lambda () (make-resource "resource" "test:///resource" #f #:workflow 'invalid))
                        (lambda () (make-prompt "prompt" '() #f #:workflow 'invalid))))])
  (check-exn exn:fail? construct))
;; Raw structs and copies must meet the same contract at interface assembly.
(for ([construct (in-list
                  (list (lambda () (make-interface #:server (server-descriptor 42 "1" "")))
                        (lambda () (make-interface #:server (server-descriptor "server" 42 "")))
                        (lambda () (make-interface #:server (server-descriptor "server" "1" 42)))
                        (lambda () (make-interface #:tools (list (struct-copy tool-descriptor good-tool [description 42]))))
                        (lambda () (make-interface #:tools (list (struct-copy tool-descriptor good-tool [execution 'invalid]))))
                        (lambda () (make-interface #:tools (list (struct-copy tool-descriptor good-tool [annotations (hasheq 'destructiveHint 42)]))))
                        (lambda () (make-interface #:resources (list (struct-copy resource-descriptor good-resource [mime-type 42]))))
                        (lambda () (make-interface #:resources (list (struct-copy resource-descriptor good-resource [handler 42]))))
                        (lambda () (make-interface #:prompts (list (struct-copy prompt-descriptor good-prompt [description 42]))))
                        (lambda () (make-interface #:prompts (list (struct-copy prompt-descriptor good-prompt [arguments (list (argument 'n Integer #f #f))]))))))])
  (check-exn exn:fail? construct))
(check-equal? calls 0)

;; Required keyword arguments are not satisfiable by runtime positional calls.
(define (keyword-handler _ #:required required) required)
(check-exn #rx"handler" (lambda () (make-tool "keyword" '() keyword-handler)))
(check-exn #rx"handler" (lambda () (make-prompt "keyword" '() keyword-handler)))
(check-exn #rx"matcher" (lambda () (make-resource "keyword" "test:///keyword" handler #:matcher keyword-handler)))
(check-exn #rx"interned" (lambda () (make-tool "uninterned" (list (argument (string->uninterned-symbol "x") String #f #f)) handler)))
(for ([value (in-list (list 1/3 +inf.0 (vector 1) handler))])
  (check-exn exn:fail? (lambda () (make-tool "json" '() handler #:annotations (hasheq 'extension value)))))
(define cycle (make-hasheq))
(hash-set! cycle 'self cycle)
(check-exn #rx"cyclic" (lambda () (make-tool "cycle" '() handler #:annotations cycle)))
(check-exn #rx"limit" (lambda () (make-tool "deep" '() handler
  #:annotations (hasheq 'extension (for/fold ([value #f]) ([i (in-range 130)]) (list value))))))
(check-exn #rx"interned" (lambda () (make-tool "keys" '() handler
  #:annotations (hasheq (string->uninterned-symbol "readOnlyHint") #t))))
(for ([key '(readOnlyHint destructiveHint idempotentHint openWorldHint)] [value '(#f #t #f #t)])
  (check-not-exn (lambda () (make-tool "annotation" '() handler #:annotations (hasheq key value)))))
(define annotations (hasheq 'title "title" 'extension (list #f json-null 1/2 (hasheq 'nested "value"))))
(check-equal? (tool-descriptor-annotations (make-tool "extended" '() handler #:annotations annotations)) annotations)

;; Domain defaults and metadata expressions run at their documented boundary;
;; contract inspection must not invoke any handler/default/completion callback.
(define defaults 0)
(define default-argument (argument 'name String #t (lambda (_) (set! defaults (add1 defaults)) "Ada")))
(define with-default (make-tool "default" (list default-argument) handler))
(define described (make-prompt "described" (list default-argument) handler))
(define completed (completion-descriptor described 'name (lambda (_prefix _context) (error 'test "completion executed"))))
(check-not-exn (lambda () (make-interface #:tools (list with-default) #:prompts (list described) #:completions (list completed))))
(check-equal? defaults 0)
(check-equal? calls 0)

;; Macros call the same checked factories, including dynamic metadata values.
(for ([make-declaration (in-list
       (list (lambda () (let ([description 42]) (tool (invalid) #:description description (text-result "never")) invalid))
             (lambda () (let ([description 42]) (resource (invalid) #:uri "test:///invalid" #:description description "never") invalid))
             (lambda () (let ([description 42]) (prompt (invalid) #:description description "never") invalid))
             (lambda () (server #:name 42 #:version "1"))
             (lambda () (tool (invalid) #:annotations (hasheq 'readOnlyHint "yes") (text-result "never")))) )])
  (check-exn exn:fail? make-declaration))

;; Durable resources/prompts may omit their ordinary handler. Tools need the
;; dispatcher procedure even when they carry a workflow for Tasks execution.
(define program (make-workflow "program" "1" "fixed" (list (workflow-stage 'done 'complete Any (lambda (_) "done") #f #f))))
(check-not-exn (lambda () (make-resource "durable" "test:///durable" #f #:workflow program)))
(check-not-exn (lambda () (make-prompt "durable" '() #f #:workflow program)))
(check-exn #rx"handler" (lambda () (make-tool "durable" '() #f #:workflow program)))
(check-exn #rx"handler" (lambda () (make-resource "missing" "test:///missing" #f)))
(check-exn #rx"handler" (lambda () (make-prompt "missing" '() #f)))

;; Compare the public DSL with ordinary data construction through real dispatch,
;; then validate the published records against the pinned independent wire schema.
(define metadata-evaluations 0)
(tool (parity [name String #:default "Ada"])
  #:description (begin (set! metadata-evaluations (add1 metadata-evaluations)) "description")
  #:annotations annotations
  (text-result name))
(define data-parity
  (make-tool "parity" (list (argument 'name String #t (lambda (_) "Ada")))
             (lambda (args) (text-result (hash-ref args 'name)))
             #:description "description" #:annotations annotations))
(define-runtime-path protocol-schema "../vendor/protocol/schema/2026-07-28/schema.json")
(define wire-schema (string->json (file->string protocol-schema)))
(define runtimes
  (for/list ([descriptor (in-list (list parity data-parity))])
    (make-runtime (make-interface #:server (server-descriptor "contracts" "1" #f)
                                 #:tools (list descriptor) #:resources (list good-resource) #:prompts (list good-prompt)))))
(dynamic-wind void
  (lambda ()
    (define (call rt method [args (hasheq)])
      (dispatch rt method (hash-set args '_meta (request-meta))))
    (check-equal? (hash-ref (call (car runtimes) "tools/list") 'tools)
                  (hash-ref (call (cadr runtimes) "tools/list") 'tools))
    (for ([rt (in-list runtimes)])
      (define discovery (call rt "server/discover"))
      (check-equal? (hash-ref discovery 'instructions) "")
      (check-true (valid? (hash-set wire-schema '$ref "#/$defs/DiscoverResult") discovery))
      (for ([method '("tools/list" "resources/list" "prompts/list")]
            [key '(tools resources prompts)] [kind '("Tool" "Resource" "Prompt")])
        (for ([record (in-list (hash-ref (call rt method) key))])
          (check-true (valid? (hash-set wire-schema '$ref (string-append "#/$defs/" kind)) record))))
      (check-equal? (hash-ref (call rt "tools/call" (hasheq 'name "parity")) 'content)
                    (list (text-content "Ada"))))
    (check-equal? metadata-evaluations 1))
  (lambda () (for ([rt (in-list runtimes)]) (custodian-shutdown-all (runtime-custodian rt)))))

;; Runtime installation also validates raw interfaces before any recovery or
;; dispatch can use their declarations.
(check-exn #rx"description" (lambda ()
  (make-runtime (interface-descriptor #f
    (list (struct-copy tool-descriptor good-tool [description 42])) '() '() '()))))
(check-exn #rx"handler" (lambda ()
  (make-runtime (interface-descriptor #f '()
    (list (struct-copy resource-descriptor good-resource [handler #f])) '() '()))))
(check-exn #rx"string codec" (lambda ()
  (make-runtime (interface-descriptor #f '() '()
    (list (struct-copy prompt-descriptor good-prompt [arguments (list (argument 'n Integer #f #f))])) '()))))

(module normalized mcp/lang
  (server #:name "normalized" #:version "1" #:instructions #f))
(require (prefix-in app: (submod "." normalized))
         (prefix-in static: (submod "." normalized manifest)))
(define normalized-instructions
  (hash-ref (hash-ref (hash-ref (car static:manifest) 'metadata) 'instructions) 'value))
(check-equal? normalized-instructions "")
(check-equal? normalized-instructions (server-descriptor-instructions (interface-descriptor-server app:mcp-interface)))
(module unknown-instructions mcp/lang
  (server #:name "unknown" #:version "1" #:instructions (error 'test "metadata was evaluated")))
(require (prefix-in unknown: (submod "." unknown-instructions manifest)))
(check-false (hash-ref (hash-ref (hash-ref (car unknown:manifest) 'metadata) 'instructions) 'known?))
