#lang racket/base
(require "runtime-binding.rkt" "runtime-state.rkt"
         "../authorization.rkt"
         (submod "../build.rkt" private)
         "../descriptor.rkt"
         "../workflow.rkt"
         "../storage.rkt"
         "../rendering.rkt"
         "../error.rkt"
         "embedded-content.rkt")
(provide input-required? render-runtime-call make-runtime-resource-resolver)
(define current-embedding-stack (make-parameter '()))
(define (input-required? result)
  (and (hash? result) (equal? (hash-ref result 'resultType #f) "input_required")
       (string? (hash-ref result 'requestState #f)) (hash? (hash-ref result 'inputRequests #f))))
(define (render-runtime-call rt method params context dispatch compute fingerprint)
  (define principal (request-context-principal context))
  (define id (request-context-request-id context))
  (define notify (request-context-notify context))
  (define meta (hash-ref params '_meta))
  (define store (runtime-store rt))
  (define existing-render
    (and store (not (current-workflow-state)) (current-workflow-invocation-key)
         (find-instance-by-key store (principal-key principal) (string-append "render:" method) (current-workflow-invocation-key))))
  (define token (or (current-workflow-state) (and existing-render (stored-instance-handle existing-render))))
  (define resumed? (render-continuation? store token))
  (define saved-workflow
    (and store token (not resumed?)
         (let ([round (resolve-continuation store token)]) (load-instance store (if round (car round) token)))))
  (define render-key
    (or (current-workflow-invocation-key)
        (and saved-workflow (string-append "workflow-render:" (stored-instance-handle saved-workflow)))))
  (define next (if saved-workflow (next-embedding-index (stored-instance-state saved-workflow)) 0))
  (define layout (if resumed? #f (parameterize ([current-render-capture (and store (box next))]) (compute))))
  (if (or resumed? (and store (layout-embeddings? layout)))
      (render-layout store layout #:operation method
                     #:arguments (or (current-render-arguments) (render-request-arguments params))
                     #:bindings (current-render-bindings)
                     #:principal (principal-key principal) #:fingerprint (bind-build-identity fingerprint)
                     #:state (and resumed? token) #:responses (current-workflow-responses)
                     #:key render-key
                     #:authorize (lambda (uri)
                                   (unless ((runtime-authorize rt) principal "resources/read" (hasheq 'uri uri '_meta meta))
                                     (mcp-error -32001 "Embedded resource is not authorized")))
                     #:resolve
                     (lambda (uri child-state child-responses key)
                       (when (or (member uri (current-embedding-stack)) (>= (length (current-embedding-stack)) 32))
                         (mcp-error -32603 "Resource embedding cycle or depth limit"))
                       (parameterize ([current-embedding-stack (cons uri (current-embedding-stack))]
                                      [current-workflow-invocation-key key])
                         (dispatch rt "resources/read"
                                   (if child-state (hasheq '_meta meta 'uri uri 'requestState child-state 'inputResponses child-responses)
                                       (hasheq '_meta meta 'uri uri))
                                   #:principal principal #:id id #:notify notify))))
      layout))
(define (make-runtime-resource-resolver rt meta context dispatch)
  (define principal (request-context-principal context))
  (define id (request-context-request-id context))
  (define notify (request-context-notify context))
  (lambda (ref)
    (define uri (resource-uri ref))
    (when (member uri (current-embedding-stack)) (mcp-error -32603 "Resource embedding cycle"))
    (when (>= (length (current-embedding-stack)) 32) (mcp-error -32603 "Resource embedding depth exceeded"))
    (parameterize ([current-embedding-stack (cons uri (current-embedding-stack))])
      (define result (dispatch rt "resources/read" (hasheq '_meta meta 'uri uri) #:principal principal #:id id #:notify notify))
      (embedded-resource-content result))))
