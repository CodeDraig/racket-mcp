#lang racket/base
(require racket/string net/base64 "../error.rkt" "request-meta.rkt")
(provide encode-header-value decode-header-value request-headers)
(define (encode-header-value value)
  (if (and (regexp-match? #px"^[ -~]*$" value) (equal? value (string-trim value))
           (not (and (string-prefix? value "=?base64?") (string-suffix? value "?=")))) value
      (string-append "=?base64?" (bytes->string/utf-8 (base64-encode (string->bytes/utf-8 value) #"")) "?=")))
(define (decode-header-value value)
  (if (and (string-prefix? value "=?base64?") (string-suffix? value "?="))
      (let* ([encoded (substring value 9 (- (string-length value) 2))]
             [raw (base64-decode (string->bytes/utf-8 encoded))])
        (unless (equal? encoded (bytes->string/utf-8 (base64-encode raw #""))) (mcp-error -32020 "Malformed header encoding"))
        (bytes->string/utf-8 raw)) value))
(define (request-headers method params)
  (append (list (cons "Content-Type" "application/json") (cons "Accept" "application/json, text/event-stream")
                (cons "MCP-Protocol-Version" protocol-version) (cons "Mcp-Method" method))
          (if (member method '("tools/call" "prompts/get" "resources/read"))
              (list (cons "Mcp-Name" (encode-header-value (hash-ref params (if (equal? method "resources/read") 'uri 'name))))) '())))
