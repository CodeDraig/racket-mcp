#lang racket/base
(require rackunit racket/file)
(define (at-phase phase form)
  (if (zero? phase) form `(begin-for-syntax ,(at-phase (sub1 phase) form))))
(define (write-module path forms)
  (call-with-output-file path
    (lambda (out)
      (displayln "#lang racket/base" out)
      (for ([form (in-list forms)]) (write form out) (newline out)))))
(test-case "public binding queries survive renamed re-exports at phases zero through two"
  (define directory (make-temporary-file "mcp-extension-phase-~a" 'directory))
  (dynamic-wind void
    (lambda ()
      (write-module (build-path directory "provider.rkt")
        '((require mcp)
          (provide Label echo document greeting)
          (schema Label String)
          (tool (echo [value Label]) (error 'test "handler must not run"))
          (resource (document [id Label]) #:uri "phase:///{id}" (error 'test "reader must not run"))
          (prompt (greeting [name Label]) (error 'test "prompt must not run"))))
      (write-module (build-path directory "forwarder.rkt")
        '((require (rename-in "provider.rkt" [Label LabelAlias] [echo EchoAlias]
                             [document DocumentAlias] [greeting GreetingAlias]))
          (provide (rename-out [LabelAlias PublicSchema] [EchoAlias PublicOperation]
                               [DocumentAlias PublicResource] [GreetingAlias PublicPrompt]))))
      (for ([phase '(0 1 2)])
        (define consumer (build-path directory (format "consumer-~a.rkt" phase)))
        (define imports
          (append (for/list ([level (in-range (add1 phase))]) `(for-meta ,level racket/base))
                  (list `(for-meta ,phase "forwarder.rkt")
                        `(for-meta ,(add1 phase) racket/base syntax/parse mcp/extension))))
        (define query
          '(define-syntax describe
             (syntax-parser
               [(_ name:id)
                (define info (lookup-mcp-binding #'name))
                (when info
                  (require-mcp-binding #'name '(schema operation resource prompt)))
                #`'#,(and info (list (mcp-binding-info-kind info)
                                     (mcp-binding-info-name info)
                                     (mcp-binding-info-arguments info)))])))
        (define result
          '(define result
             (list (describe PublicSchema) (describe PublicOperation)
                   (describe PublicResource) (describe PublicPrompt)
                   (describe string-append)
                   (let ([PublicResource "host"]) (describe PublicResource)))))
        (define lowerings
          (for/list ([level (in-range (sub1 phase) -1 -1)])
            (at-phase level
              '(begin
                 (define-syntax (lower stx) #`'#,result)
                 (define result (lower))))))
        (write-module consumer
          (append (list `(require ,@imports) (at-phase phase query)
                        (at-phase phase result)) lowerings '((provide result))))
        (parameterize ([current-namespace (make-base-namespace)])
          (check-equal? (dynamic-require consumer 'result)
                        '((schema #f #f) (operation #f #f)
                          (resource document (id)) (prompt greeting (name)) #f #f)
                        (format "phase ~a" phase)))
        (define invalid (build-path directory (format "invalid-~a.rkt" phase)))
        (write-module invalid
          (list `(require ,@imports)
                (at-phase phase
                  '(define-syntax only-resource
                     (syntax-parser
                       [(_ name:id)
                        (require-mcp-binding #'name '(resource) #:context this-syntax)
                        #'#t])))
                (at-phase phase '(only-resource PublicPrompt))))
        (parameterize ([current-namespace (make-base-namespace)])
          (check-exn
            (lambda (e)
              (and (exn:fail:syntax? e)
                   (regexp-match? #rx"expected MCP resource binding" (exn-message e))
                   (for/or ([source (in-list (exn:fail:syntax-exprs e))])
                     (and (eq? (syntax-e source) 'PublicPrompt)
                          (equal? (syntax-source source) invalid)
                          (exact-positive-integer? (syntax-line source))))))
            (lambda () (dynamic-require invalid #f))
            (format "wrong-kind source diagnostic at phase ~a" phase)))))
    (lambda () (delete-directory/files directory))))
