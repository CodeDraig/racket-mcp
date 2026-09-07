#lang racket/base
(require "../json.rkt")
(provide check-server-message check-result-capabilities!)

(define (request-id? v) (or (string? v) (exact-integer? v)))
(define (object-meta? v)
  (and (hash? v) (hash? (hash-ref v '_meta (hasheq)))))
(define (check-result-capabilities! message capabilities)
  (when (hash-has-key? message 'result)
    (define type (hash-ref (hash-ref message 'result) 'resultType "complete"))
    (unless (or (member type '("complete" "input_required"))
                (and (equal? type "task")
                     (hash-has-key? (hash-ref capabilities 'extensions (hasheq))
                                    'io.modelcontextprotocol/tasks)))
      (error 'client "Unrecognized or unadvertised resultType: ~e" type))))

;; Check the envelope independently of method-specific result contracts. Missing
;; resultType retains the core specification's required 'complete' interpretation.
;; An error without an ID is legal when the sender could not read the request ID.
(define (check-server-message m #:expected-id [expected missing])
  (unless (and (hash? m) (equal? (hash-ref m 'jsonrpc #f) "2.0"))
    (error 'client "Invalid JSON-RPC envelope"))
  (define id (hash-ref m 'id missing))
  (define method (hash-ref m 'method missing))
  (define result? (hash-has-key? m 'result))
  (define error? (hash-has-key? m 'error))
  (define kind
    (cond
      [(not (missing? method))
       (unless (and (string? method) (missing? id) (not result?) (not error?)
                    (object-meta? (hash-ref m 'params (hasheq))))
         (error 'client "Invalid notification or unexpected server request"))
       'notification]
      [else
       (unless (and (not (eq? result? error?))
                    (or (request-id? id) (and error? (missing? id))))
         (error 'client "Invalid response envelope"))
       (when (and (not (missing? expected)) (not (missing? id)) (not (equal? id expected)))
         (error 'client "Unrelated response ID"))
       (cond
         [result?
          (define result (hash-ref m 'result))
          (unless (and (object-meta? result)
                       (member (hash-ref result 'resultType "complete") '("complete" "input_required" "task")))
            (error 'client "Invalid result object or unrecognized resultType"))]
         [else
          (define e (hash-ref m 'error))
          (unless (and (hash? e) (exact-integer? (hash-ref e 'code #f))
                       (string? (hash-ref e 'message #f)))
            (error 'client "Invalid error object"))])
       (if (missing? id) 'uncorrelated-error 'response)]))
  kind)
