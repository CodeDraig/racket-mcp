#lang mcp
(require racket/match "lang-marker.rkt" "../../examples/extensions/checkpoint-copy.rkt"
         (for-syntax racket/base))
(provide expansion-count calls)
(server #:name "match-language" #:version "1")
(begin-for-syntax (define count 0))
(define-match-expander tagged
  (lambda (stx)
    (set! count (add1 count))
    (syntax-case stx () [(_ value) #'(list "tag" value)])))
(define calls 0)
(define (observe value) (set! calls (add1 calls)) value)
(workflow (language-match [items Any]) #:version "1"
  (match items
    [(app observe (tagged value))
     (checkpoint-copy [saved String] value)
     (text-result saved)]))
(define-syntax (compiled-count stx) #`#,count)
(define expansion-count (compiled-count))
(set-box! loaded #t)
