#lang racket/base
(require "../error.rkt")
(provide capture-snapshot check-upstream-compatibility! result!)
(define methods '("server/discover" "tools/list" "resources/list" "resources/templates/list" "prompts/list"))
(define (result! outcome)
  (when (and (not (hash-has-key? outcome 'resultType)) (hash-has-key? outcome 'error))
    (define failure (hash-ref outcome 'error))
    ;; Capability requirements retain their meaning across the bridge. Do not
    ;; turn an actionable client capability error into an internal SDK failure.
    (when (and (hash? failure) (equal? (hash-ref failure 'code #f) -32021))
      (mcp-error -32021 "Upstream requires additional client capabilities" (hash-ref failure 'data #f)))
    (mcp-error -32603 "Upstream request failed" failure))
  (if (hash-has-key? outcome 'resultType) outcome (hash-ref outcome 'result outcome)))
(define (capture-snapshot request)
  (define discovery (result! (request "server/discover" (hasheq))))
  (define capabilities (hash-ref discovery 'capabilities (hasheq)))
  (for/hasheq ([method (in-list methods)])
    (define key (case (string->symbol method) [(tools/list) 'tools] [(resources/list) 'resources] [(resources/templates/list) 'resourceTemplates] [(prompts/list) 'prompts] [else #f]))
    (define capability (case (string->symbol method) [(tools/list) 'tools] [(prompts/list) 'prompts] [else 'resources]))
    (define result (cond [(not key) discovery]
                         [(hash-has-key? capabilities capability) (result! (request method (hasheq)))]
                         [else (hasheq 'resultType "complete" key '() 'ttlMs 0 'cacheScope "private")]))
    (define all
      (if (not key) result
          (let loop ([page result] [items '()] [seen '()])
            (define combined (append items (hash-ref page key)))
            (define next (hash-ref page 'nextCursor #f))
            (cond [(not next) (hash-set (hash-remove result 'nextCursor) key combined)]
                  [(member next seen) (error 'capture-snapshot "upstream repeated a pagination cursor")]
                  [else (loop (result! (request method (hasheq 'cursor next))) combined (cons next seen))]))))
    (values (string->symbol method) all)))
(define (check-upstream-compatibility! snapshot request)
  (define fresh (capture-snapshot request))
  (for ([field '(supportedVersions capabilities)])
    (unless (equal? (hash-ref (hash-ref snapshot 'server/discover) field)
                    (hash-ref (hash-ref fresh 'server/discover) field))
      (error 'upstream "pinned discovery changed; refresh and review the snapshot")))
  (for ([method '(tools/list prompts/list resources/list resources/templates/list)])
    (define field (case method [(tools/list) 'tools] [(prompts/list) 'prompts] [(resources/list) 'resources] [else 'resourceTemplates]))
    (unless (equal? (hash-ref (hash-ref snapshot method) field) (hash-ref (hash-ref fresh method) field))
      (error 'upstream "pinned interface changed; refresh and review the snapshot"))) #t)
