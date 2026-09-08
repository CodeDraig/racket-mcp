#lang racket/base
(require (for-syntax racket/base syntax/parse))
(provide module-begin/finish)
;; This is a compiler boundary, not another module-end lift. Full expansion
;; drains user lifts first. The trusted final expression is then expanded and
;; appended to the resulting body, so failed user initialization cannot reach it.
(define-syntax (module-begin/finish stx)
  (syntax-parse stx
    [(_ #:finish finish:expr
        (~optional (~seq #:module-begin original:id)
                   #:defaults ([original #'#%plain-module-begin]))
        body ...)
     (define expanded
       (local-expand #'(original body ...) 'module-begin '()))
     (define final (local-expand #'finish 'expression '()))
     (syntax-parse expanded
       [(head expanded-body ...)
        #`(head expanded-body ... #,final)])]))
