#lang racket/base
(require "main.rkt" "cli.rkt" "completion.rkt" "private/registration.rkt" racket/splicing
         (for-syntax racket/base racket/list syntax/parse "private/module-compiler.rkt"))
(provide (except-out (all-from-out racket/base) #%module-begin module+ module*) (all-from-out "main.rkt")
         (rename-out [mcp-module-begin #%module-begin] [mcp-module+ module+] [mcp-module* module*]))
;; The enclosing form supplies the implicit module-begin context. Keep that
;; context in racket/base while preserving each user's body syntax unchanged.
(define-syntax (mcp-module+ stx)
  (syntax-parse stx
    [(_ name:id body ...) (syntax/loc stx (module+ name body ...))]))
(define-syntax (mcp-module* stx)
  (syntax-parse stx
    [(_ name:id language body ...) (syntax/loc stx (module* name language body ...))]))
(define-syntax (mcp-module-begin stx)
  (syntax-parse stx
    [(_ form ...)
     (define tools '()) (define resources '()) (define prompts '()) (define servers '()) (define manifest '())
     (define expanded
       (for/list ([f (in-list (syntax->list #'(form ...)))])
         (syntax-parse f #:literals (server tool resource prompt workflow)
           [(server . _) (set! servers (cons f servers)) f]
           [((~and kind (~or tool resource prompt workflow)) (id:id . _) . _)
            (case (syntax-e #'kind)
              [(tool workflow) (set! tools (cons #'id tools))] [(resource) (set! resources (cons #'id resources))] [(prompt) (set! prompts (cons #'id prompts))])
            (set! manifest (cons (hasheq 'kind (syntax-e #'kind) 'name (syntax-e #'id)
                                        'source (format "~a" (syntax-source f)) 'line (syntax-line f)
                                        'dynamic-metadata #t) manifest)) f]
           [_ f])))
     (when (> (length servers) 1) (raise-syntax-error #f "only one server declaration is allowed" stx (car servers)))
     (for ([ids (list tools resources prompts)])
       (define seen (make-hash))
       (for ([id (in-list (reverse ids))])
         (when (hash-ref seen (syntax-e id) #f) (raise-syntax-error #f "duplicate published name" stx id))
         (hash-set! seen (syntax-e id) #t)))
     ;; mcp-interface is deliberately a conventional user-visible binding.
     (define interface-id (datum->syntax stx 'mcp-interface))
     (define compiler-ids (generate-temporaries '(collect finish)))
     (define collect (car compiler-ids)) (define finish (cadr compiler-ids))
     #`(#%plain-module-begin
        (define declarations '())
        (define (register! descriptor) (set! declarations (cons descriptor declarations)))
        (define-syntaxes (#,collect #,finish) (make-module-compilers #'register!))
        (splicing-syntax-parameterize ([register-declaration (make-rename-transformer (quote-syntax #,collect))]) #,@expanded)
        (define collected-servers (filter server-descriptor? declarations))
        (define mounted (filter interface-descriptor? declarations))
        (when (> (length collected-servers) 1) (error 'mcp "only one server declaration is allowed"))
        (define #,interface-id (make-interface #:server (and (pair? collected-servers) (car collected-servers))
                                              #:requirements (interface-requirements (apply mount-interfaces mounted))
                                              #:adapter-bindings (interface-adapter-bindings (apply mount-interfaces mounted))
                                              #:adapter-restrictions (interface-adapter-restrictions (apply mount-interfaces mounted))
                                              #:references (interface-resource-references (apply mount-interfaces mounted))
                                              #:tools (append (reverse (filter tool-descriptor? declarations)) (apply append (map interface-descriptor-tools mounted)))
                                              #:resources (append (reverse (filter resource-descriptor? declarations)) (apply append (map interface-descriptor-resources mounted)))
                                              #:prompts (append (reverse (filter prompt-descriptor? declarations)) (apply append (map interface-descriptor-prompts mounted)))
                                              #:completions (append (reverse (filter completion-descriptor? declarations)) (apply append (map interface-descriptor-completions mounted)))))
        (provide #,interface-id)
        (define-values () (begin (#,finish) (values)))
        (module+ main (serve-interface-command #,interface-id)))]))
