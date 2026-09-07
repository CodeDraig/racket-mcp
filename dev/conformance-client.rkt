#lang racket/base
(require racket/list mcp/http mcp/json mcp/interaction)
(define args (current-command-line-arguments))
(define client (make-http-client (vector-ref args (sub1 (vector-length args)))))
(define (call method [params (hasheq)])
  (define response (run-interaction
    (lambda (method params) (http-client-call client method params #:capabilities (hasheq 'elicitation (hasheq))))
    method params #:elicit (lambda (_) (hasheq 'action "decline")) #:navigate (lambda (_) (hasheq 'action "cancel"))))
  (hash-ref response 'result (hasheq)))
(void (call "server/discover"))
(define tools (hash-ref (call "tools/list") 'tools '()))
(define context (let ([value (getenv "MCP_CONFORMANCE_CONTEXT")]) (if value (string->json value) (hasheq))))
;; Authored harness arguments exercise null, Unicode, and control characters;
;; do not replace them with generated examples.
(define supplied-calls (hash-ref context 'toolCalls '()))
(for ([entry (in-list supplied-calls)])
  (void (call "tools/call" (hasheq 'name (hash-ref entry 'name) 'arguments (hash-ref entry 'arguments)))))
(for ([tool (in-list tools)] #:unless (member (hash-ref tool 'name) (map (lambda (entry) (hash-ref entry 'name)) supplied-calls)))
  (define properties (hash-ref (hash-ref tool 'inputSchema (hasheq)) 'properties (hasheq)))
  (define arguments
    (if (equal? (hash-ref tool 'name) "json_schema_echo")
        (hasheq 'schema (hash-ref (findf (lambda (candidate) (equal? (hash-ref candidate 'name) "json_schema_2020_12_tool")) tools) 'inputSchema))
    (for/hasheq ([(name schema) (in-hash properties)])
      (values name (hash-ref schema 'default
                            (lambda () (case (string->symbol (hash-ref schema 'type "string"))
                                         [(integer number) 1] [(boolean) #t] [else "test"])))))))
  (void (call "tools/call" (hasheq 'name (hash-ref tool 'name) 'arguments arguments))))
(define resources (hash-ref (call "resources/list") 'resources '()))
(for ([resource (in-list resources)]) (void (call "resources/read" (hasheq 'uri (hash-ref resource 'uri)))))
(define prompts (hash-ref (call "prompts/list") 'prompts '()))
(for ([prompt (in-list prompts)])
  (void (call "prompts/get" (hasheq 'name (hash-ref prompt 'name)
                                   'arguments (for/hasheq ([arg (in-list (hash-ref prompt 'arguments '()))]) (values (string->symbol (hash-ref arg 'name)) "test"))))))
