#lang racket/base
(require (for-syntax racket/base syntax/parse))
(provide module-begin/finish)
;; This is a compiler boundary, not another module-end lift. Full expansion
;; drains user lifts first. The trusted final expression is then expanded and
;; appended to the resulting body, so failed user initialization cannot reach it.
(define-syntax (module-begin/finish stx)
  (syntax-parse stx
    [(_ #:finish finish:expr
        (~optional (~seq #:parameterize ([parameter:id value:expr] ...))
                   #:defaults ([(parameter 1) '()] [(value 1) '()]))
        (~optional (~seq #:exclude (excluded:id ...))
                   #:defaults ([(excluded 1) '()]))
        (~optional (~seq #:module-begin original:id)
                   #:defaults ([original #'#%plain-module-begin]))
        body ...)
     (define expanded
       (local-expand #'(original body ...) 'module-begin '()))
     (define final (local-expand #'finish 'expression '()))
     ;; Apply dynamic scope only to phase-zero initialization after all lifts
     ;; are known. Acquisition bindings, transformer phases, and submodules keep
     ;; their own lifetimes. The trusted completion expression remains outside.
     (define pending-acquisitions (syntax->list #'(excluded ...)))
     (define (scope-expression expression)
       (if (or (pair? pending-acquisitions)
               (null? (syntax->list #'(parameter ...)))) expression
           (local-expand #`(parameterize ([parameter value] ...) #,expression)
                         'expression '())))
     (define (scope-form form)
       (syntax-parse form
         #:literals (define-values begin define-syntaxes begin-for-syntax
                                   module module* #%require #%provide #%declare)
         [(define-values (id ...) rhs)
          (if (for/or ([id (in-list (syntax->list #'(id ...)))])
                (for/or ([exclude (in-list (syntax->list #'(excluded ...)))])
                  (free-identifier=? id exclude)))
              (begin
                (set! pending-acquisitions
                  (filter (lambda (exclude)
                            (not (for/or ([id (in-list (syntax->list #'(id ...)))])
                                   (free-identifier=? id exclude))))
                          pending-acquisitions))
                form)
              (with-syntax ([scoped (scope-expression #'rhs)])
                (syntax/loc form (define-values (id ...) scoped))))]
         [(begin nested ...)
          (with-syntax ([(scoped ...) (map scope-form (syntax->list #'(nested ...)))])
            (syntax/loc form (begin scoped ...)))]
         [((~or define-syntaxes begin-for-syntax module module* #%require #%provide #%declare) . _) form]
         [_ (scope-expression form)]))
     (syntax-parse expanded
       [(head expanded-body ...)
        (define scoped
          (if (null? (syntax->list #'(parameter ...)))
              (syntax->list #'(expanded-body ...))
              (map scope-form (syntax->list #'(expanded-body ...)))))
        (when (and (pair? (syntax->list #'(parameter ...))) (pair? pending-acquisitions))
          (raise-syntax-error #f "initialization scope has unresolved acquisition bindings"
                              stx (car pending-acquisitions)))
        #`(head #,@scoped #,final)])]))
