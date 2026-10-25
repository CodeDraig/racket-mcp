#lang racket/base
(require "../json.rkt" (submod "../build.rkt" private) "runtime-state.rkt" "persistent-json.rkt" "../clock.rkt"
         "../descriptor.rkt" "../authorization.rkt" "../workflow.rkt"
         "../rendering.rkt" "../storage.rkt" "../error.rkt")
(provide bind-call-arguments current-render-bindings current-render-arguments render-request-arguments)
(define current-render-arguments (make-parameter #f))
(define current-render-bindings (make-parameter (hasheq)))
(define (render-request-arguments params)
  (persistent-json (hash-remove (hash-remove (hash-remove params '_meta) 'requestState) 'inputResponses)))
(define (bind-call-arguments rt method params arguments input program fingerprint)
  (define store (runtime-store rt))
  (define principal (principal-key (request-context-principal (current-request-context))))
  (define keyed (and store (not (current-workflow-state)) (current-workflow-invocation-key)
                     (find-instance-by-key store principal (string-append "render:" method) (current-workflow-invocation-key))))
  (define token (or (current-workflow-state) (and keyed (stored-instance-handle keyed))))
  (define rendering? (render-continuation? store token))
  (define saved
    ;; Upstream handlers own their non-render continuation formats.
    (and store token (or rendering? program)
         (let* ([round (and (not rendering?) (resolve-continuation store token))]
                [instance (or (load-instance store (if round (car round) token))
                              (mcp-error -32602 "Unknown continuation"))]
                [operation (if rendering? (string-append "render:" method)
                               (and program (if (equal? method "tools/call") (workflow-descriptor-name program)
                                                (string-append method ":" (workflow-descriptor-name program)))))])
           (unless (and (equal? principal (stored-instance-principal instance))
                        (equal? operation (stored-instance-operation instance)))
             (mcp-error -32602 "Continuation belongs to another principal or operation"))
           (when (<= (stored-instance-expires instance) (mcp-current-seconds))
             (mcp-error -32602 "Continuation has expired"))
           (unless (and (equal? (stored-instance-fingerprint instance) (if rendering? (bind-build-identity fingerprint) fingerprint))
                        (equal? (stored-instance-version instance) (if rendering? "render/3" (workflow-descriptor-version program))))
             (raise (exn:fail:recovery "Continuation executable is incompatible with retained identity" (current-continuation-marks) (stored-instance-handle instance) #f)))
           instance)))
  (define (retained-render-bindings)
    (define retained (hash-ref (stored-instance-state saved) 'bindings #f))
    (or retained
        (and program
             (let* ([operation (if (equal? method "tools/call") (workflow-descriptor-name program)
                                   (string-append method ":" (workflow-descriptor-name program)))]
                    [matches
                     (filter
                       (lambda (flow)
                         (and (equal? principal (stored-instance-principal flow))
                              (let ([render (find-instance-by-key store principal (string-append "render:" method)
                                              (string-append "workflow-render:" (stored-instance-handle flow)))])
                                (and render (equal? (stored-instance-handle render) (stored-instance-handle saved))))))
                       (list-instances store #:operation operation))])
               (when (> (length matches) 1) (mcp-error -32602 "Rendering argument evidence is ambiguous"))
               (and (pair? matches)
                    (let ([flow (car matches)])
                      (unless (and (> (stored-instance-expires flow) (mcp-current-seconds))
                                   (equal? fingerprint (stored-instance-fingerprint flow))
                                   (equal? (workflow-descriptor-version program) (stored-instance-version flow)))
                        (mcp-error -32602 "Rendering argument evidence is expired or incompatible"))
                      (stored-instance-arguments flow)))))))
  (define bound
    (cond [rendering?
           (define bindings (retained-render-bindings))
           (define original (stored-instance-arguments saved))
           (define request (render-request-arguments params))
           ;; A render/3 record without bindings can recover explicitly supplied
           ;; defaults without changing any argument present in its request.
           (define comparable
             (if (and (not bindings) (hash-has-key? request 'arguments))
                 (let* ([prior (hash-ref original 'arguments (hasheq))]
                        [supplied (for/fold ([values (hash-ref request 'arguments)]) ([a (in-list arguments)]
                                     #:when (and (argument-default a) (not (hash-has-key? prior (argument-name a)))))
                                    (hash-remove values (argument-name a)))])
                   (if (or (hash-has-key? original 'arguments) (positive? (hash-count supplied)))
                       (hash-set request 'arguments supplied) (hash-remove request 'arguments)))
                 request))
           (unless (equal? comparable original)
             (mcp-error -32602 "Rendering continuation does not match this execution"))
           (current-render-arguments original)
           (if bindings
               (for/hasheq ([a (in-list arguments)])
                 (values (argument-name a) (hash-ref bindings (argument-name a) missing)))
               (begin
                 (when (ormap (lambda (a) (and (argument-default a) (not (hash-has-key? input (argument-name a))))) arguments)
                   (mcp-error -32602 "Rendering continuation predates saved argument bindings; supply omitted defaulted arguments explicitly"))
                 (bind-arguments arguments input #:defaults (hasheq))))]
          [else (bind-arguments arguments input #:defaults (and saved (stored-instance-arguments saved)))]))
  (current-render-bindings (for/hasheq ([(k v) (in-hash bound)] #:unless (missing? v)) (values k v)))
  bound)
