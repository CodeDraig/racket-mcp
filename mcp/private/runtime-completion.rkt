#lang racket/base
(require racket/list "../descriptor.rkt" "../completion.rkt" "../json.rkt" "../error.rkt")
(provide dispatch-completion)
(define (dispatch-completion iface params)
  (define ref (hash-ref params 'ref (hasheq))) (define arg (hash-ref params 'argument (hasheq)))
  (define completion
    (findf (lambda (d)
             (define target (completion-descriptor-target d))
             (and (equal? (symbol->string (completion-descriptor-argument d)) (hash-ref arg 'name #f))
                  (cond [(resource-descriptor? target) (and (equal? (hash-ref ref 'type #f) "ref/resource") (equal? (resource-descriptor-uri target) (hash-ref ref 'uri #f)))]
                        [(prompt-descriptor? target) (and (equal? (hash-ref ref 'type #f) "ref/prompt") (equal? (prompt-descriptor-name target) (hash-ref ref 'name #f)))] [else #f])))
           (interface-descriptor-completions iface)))
  (unless completion (mcp-error -32602 "Unknown completion target"))
  (define supplied ((completion-descriptor-handler completion) (hash-ref arg 'value "") (hash-ref params 'context (hasheq))))
  (define result
    (cond [(and (list? supplied) (andmap string? supplied))
           (hasheq 'values (take supplied (min 100 (length supplied))) 'total (length supplied) 'hasMore (> (length supplied) 100))]
          [(and (hash? supplied) (json-value? supplied)
                (list? (hash-ref supplied 'values #f)) (andmap string? (hash-ref supplied 'values))
                (<= (length (hash-ref supplied 'values)) 100)
                (or (not (hash-has-key? supplied 'total)) (rational? (hash-ref supplied 'total)))
                (or (not (hash-has-key? supplied 'hasMore)) (boolean? (hash-ref supplied 'hasMore)))) supplied]
          [else (mcp-error -32603 "Invalid completion values")]))
  (hasheq 'resultType "complete" 'completion result)
)
