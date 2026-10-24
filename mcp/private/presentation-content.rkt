#lang racket/base
(require net/base64 racket/list "../json.rkt" "embedded-content.rkt")
(provide text-presentation json-presentation binary-presentation resource-contents resource-content presentation-content presentation-contents)


;; These values are JSON representations, so workflow checkpoints and rendering
;; layouts can retain them without serializing procedures or ports.
(define (text-presentation #:mime-type [mime "text/plain"] . parts)
  (hasheq '$mcp/presentation "text" 'mimeType mime 'parts parts))
(define (json-presentation value)
  (hasheq '$mcp/presentation "json" 'mimeType "application/json" 'value value))
(define (binary-presentation bytes #:mime-type [mime "application/octet-stream"])
  (unless (bytes? bytes) (raise-argument-error 'binary-presentation "bytes?" bytes))
  (hasheq '$mcp/presentation "binary" 'mimeType mime 'data (bytes->string/utf-8 (base64-encode bytes #""))))
(define (resource-content value)
  (unless (and (hash? value) (json-value? value) (string? (hash-ref value 'uri #f))
               (or (and (string? (hash-ref value 'text #f)) (not (hash-has-key? value 'blob)))
                   (and (string? (hash-ref value 'blob #f)) (not (hash-has-key? value 'text))))
               (or (not (hash-has-key? value 'mimeType)) (string? (hash-ref value 'mimeType))))
    (raise-argument-error 'resource-content "JSON resource content with URI and exactly one text/blob field" value))
  (hasheq '$mcp/presentation "resource-content" 'content value))
(define (resource-contents . parts)
  (hasheq '$mcp/presentation "contents" 'parts parts))
(define (presentation-contents value uri default-mime)
  (if (and (hash? value) (equal? (hash-ref value '$mcp/presentation #f) "contents"))
      (append-map (lambda (part) (presentation-contents part uri default-mime)) (hash-ref value 'parts))
      (list (presentation-content value uri default-mime))))
(define (text-part part)
  (cond [(embedded-group? part) (apply string-append (map text-part (embedded-group-items part)))]
        [(string? part) part]
        [(and (hash? part) (equal? (hash-ref part 'type #f) "resource"))
         (define text (hash-ref (hash-ref part 'resource) 'text #f))
         (unless (string? text) (error 'text-presentation "binary content requires an explicit text conversion")) text]
        [else (error 'text-presentation "expected text or an embedded text resource")]))
(define (presentation-content value uri default-mime)
  (define (content mime key data) (hasheq 'uri uri 'mimeType mime key data))
  (cond [(string? value) (content default-mime 'text value)]
        [(bytes? value) (content default-mime 'blob (bytes->string/utf-8 (base64-encode value #"")))]
        [(hash? value)
         (define mime (hash-ref value 'mimeType default-mime))
         (unless (string? mime) (error 'presentation-content "MIME type must be a string"))
         (case (string->symbol (hash-ref value '$mcp/presentation "invalid"))
           [(resource-content) (hash-ref value 'content)]
           [(text) (content mime 'text (apply string-append (map text-part (hash-ref value 'parts))))]
           [(json) (content "application/json" 'text (json->string (embedded-json (hash-ref value 'value))))]
           [(binary) (content mime 'blob (hash-ref value 'data))]
           [else (error 'presentation-content "unknown presentation")])]
        [else (error 'presentation-content "expected text, bytes, or a presentation")]))

