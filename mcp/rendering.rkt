#lang racket/base
(require "clock.rkt" racket/list racket/string "storage.rkt" "json.rkt" "error.rkt" "private/embedded-content.rkt" "private/render-provenance.rkt" "private/persistent-json.rkt")
(provide current-render-capture deferred-embedding render-layout render-continuation? layout-embeddings? next-embedding-index)

(define current-render-capture (make-parameter #f))
(define (deferred-embedding uri)
  (define counter (current-render-capture))
  (unless (box? counter) (error 'deferred-embedding "no rendering capture"))
  (define id (unbox counter)) (set-box! counter (add1 id))
  (mark-render-value (hasheq '$mcp/embedding id 'uri uri) "embedding"))
(define (marker? value)
  (and (equal? (render-value-kind value) "embedding") (hash? value) (= (hash-count value) 2)
       (exact-nonnegative-integer? (hash-ref value '$mcp/embedding #f))
       (string? (hash-ref value 'uri #f))))
(define (walk value transform)
  (cond [(marker? value) (transform value)]
        [(hash? value)
         (define rebuilt (for/hasheq ([(k v) (in-hash value)]) (values k (walk v transform))))
         ;; Rebuilding a resolved group must retain its SDK-owned provenance.
         ;; Ordinary JSON with marker-shaped keys remains unmarked.
         (define kind (render-value-kind value))
         (if kind (mark-render-value rebuilt kind) rebuilt)]
        [(list? value) (map (lambda (v) (walk v transform)) value)]
        [else value]))
(define (render-continuation? store token)
  (and store (string? token)
       (let ([instance (load-instance store token)])
         (and instance (equal? (hash-ref (stored-instance-state instance) 'kind #f) "render")))))
(define (layout-embeddings? value)
  (define found? #f)
  (walk value (lambda (marker) (set! found? #t) marker)) found?)
(define (next-embedding-index value)
  (define next 0)
  (walk value (lambda (marker) (set! next (max next (add1 (hash-ref marker '$mcp/embedding)))) marker)) next)
(define (render-layout store layout #:operation operation #:arguments arguments #:principal principal
                       #:fingerprint fingerprint #:resolve resolve #:state [token #f]
                       #:responses [responses (hasheq)] #:ttl [ttl 86400] #:authorize [authorize void] #:key [key #f]
                       #:bindings [bindings (hasheq)])
  ;; resolve receives URI, child state, input responses, and a stable invocation
  ;; key. It must deduplicate uncertain initial child calls using that key.
  (define instance
    (if token
        (or (load-instance store token) (mcp-error -32602 "Unknown rendering continuation"))
        (let ([nodes (make-hasheq)])
          (walk layout (lambda (marker)
                         (define id (hash-ref marker '$mcp/embedding))
                         (when (and (hash-has-key? nodes id) (not (equal? (hash-ref nodes id) marker)))
                           (error 'render-layout "conflicting embedding identity"))
                         (hash-set! nodes id marker) marker))
          (when (> (hash-count nodes) 1024) (error 'render-layout "embedding count limit exceeded"))
          (create-instance! store principal (string-append "render:" operation) arguments "render/3" fingerprint
                            (+ (mcp-current-seconds) ttl)
                            (hasheq 'kind "render" 'layout layout 'history (hasheq) 'bindings bindings
                                    'children (for/list ([id (in-list (sort (hash-keys nodes) <))])
                                                (hash-set* (hash-ref nodes id) 'status "pending" 'round 0))) #:key key))))
  (unless (and (equal? (stored-instance-principal instance) principal)
               (equal? (stored-instance-operation instance) (string-append "render:" operation))
               (equal? (stored-instance-arguments instance) arguments)
               (equal? (stored-instance-fingerprint instance) fingerprint)
               (equal? (hash-ref (stored-instance-state instance) 'kind #f) "render")
               (> (stored-instance-expires instance) (mcp-current-seconds)))
    (mcp-error -32602 "Rendering continuation does not match this execution"))
  (unless (equal? (stored-instance-version instance) "render/3")
    (mcp-error -32602 "Rendering continuation version is incompatible"
               (hasheq 'expected "render/3" 'actual (stored-instance-version instance))))
  (define handle (stored-instance-handle instance))
  (define (prefix child) (format "e~a/r~a/" (hash-ref child '$mcp/embedding) (hash-ref child 'round)))
  (let loop ()
    (set! instance (load-instance store handle))
    (define state (stored-instance-state instance))
    (for ([(key answer) (in-hash responses)])
      (define prior (hash-ref (hash-ref state 'history) key missing))
      (unless (or (missing? prior) (equal? prior (persistent-json answer))) (mcp-error -32602 "Conflicting embedded input response")))
    (define children (hash-ref state 'children))
    (for ([child (in-list children)]) (authorize (hash-ref child 'uri)))
    (define child (findf (lambda (c) (not (equal? (hash-ref c 'status) "complete"))) children))
    (cond
      [(not child)
       (define results (for/hasheq ([c (in-list children)]) (values (hash-ref c '$mcp/embedding) (hash-ref c 'result))))
       (walk (hash-ref state 'layout) (lambda (marker) (hash-ref results (hash-ref marker '$mcp/embedding))))]
      [else
       (define namespace (prefix child))
       (define supplied
         (for/hasheq ([(key answer) (in-hash responses)]
                     #:when (and (string-prefix? (symbol->string key) namespace)
                                 (hash-has-key? (hash-ref child 'requests (hasheq))
                                                (string->symbol (substring (symbol->string key) (string-length namespace))))))
           (values (string->symbol (substring (symbol->string key) (string-length namespace))) (persistent-json answer))))
       (define outcome (resolve (hash-ref child 'uri) (hash-ref child 'state #f) supplied
                                (format "~a/~a" handle (hash-ref child '$mcp/embedding))))
       (define pending? (equal? (hash-ref outcome 'resultType #f) "input_required"))
       (define updated-child
         (if pending?
             (hash-set* child 'status "input_required" 'state (hash-ref outcome 'requestState)
                        'requests (hash-ref outcome 'inputRequests)
                        'round (if (and (hash-has-key? child 'state) (not (equal? (hash-ref child 'state) (hash-ref outcome 'requestState))))
                                   (add1 (hash-ref child 'round)) (hash-ref child 'round)))
             (hash-set* child 'status "complete" 'result (embedded-resource-content outcome))))
       (define saved?
         (store-transaction store
           (lambda ()
             (define latest (load-instance store handle))
             (and (= (stored-instance-revision latest) (stored-instance-revision instance))
                  (let ([history (for/fold ([history (hash-ref state 'history)]) ([(key answer) (in-hash supplied)])
                                   (hash-set history (string->symbol (string-append namespace (symbol->string key))) answer))])
                    (update-instance! store latest
                                      (hash-set* state 'history history
                                                 'children (map (lambda (c) (if (= (hash-ref c '$mcp/embedding) (hash-ref child '$mcp/embedding)) updated-child c)) children)))
                    #t)))))
       (if (and saved? pending?)
           (hasheq 'resultType "input_required" 'requestState handle
                   'inputRequests (for/hasheq ([(key request) (in-hash (hash-ref updated-child 'requests))])
                                    (values (string->symbol (string-append (prefix updated-child) (symbol->string key))) request)))
           (loop))])))
