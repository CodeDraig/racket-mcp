#lang racket/base
(require "../error.rkt" "progress.rkt")
(provide protocol-version request-meta validate-request-meta)
(define protocol-version "2026-07-28")
(define (request-meta #:capabilities [caps (hasheq)] #:extra [extra (hasheq)])
  (hash-set* extra 'io.modelcontextprotocol/protocolVersion protocol-version
             'io.modelcontextprotocol/clientCapabilities caps
             'io.modelcontextprotocol/clientInfo (hasheq 'name "racket-mcp" 'version "0.1")))
(define (validate-request-meta params #:version? [version? #t])
  (unless (hash? params) (mcp-error -32602 "params must be an object"))
  (define meta (hash-ref params '_meta #f))
  (unless (and (hash? meta) (string? (hash-ref meta 'io.modelcontextprotocol/protocolVersion #f))
               (hash? (hash-ref meta 'io.modelcontextprotocol/clientCapabilities #f)))
    (mcp-error -32602 "_meta requires protocolVersion and clientCapabilities"))
  (when (and (hash-has-key? meta 'progressToken) (not (progress-token? (hash-ref meta 'progressToken))))
    (mcp-error -32602 "progressToken must be a string or integer"))
  (define version (hash-ref meta 'io.modelcontextprotocol/protocolVersion))
  (unless (or (not version?) (equal? version protocol-version))
    (mcp-error -32022 "Unsupported protocol version" (hasheq 'supported (list protocol-version) 'requested version))) meta)
