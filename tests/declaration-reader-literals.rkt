#lang racket/base
(require rackunit racket/port mcp)
;; These are self-evaluating Racket reader literals, but none is a JSON Schema.
;; Expansion must diagnose the literal without waiting for module instantiation.
(define literals '("#rx\"abc\"" "#rx#\"abc\"" "#&1" "#s(record 1)"))
(define declarations
  '("(schema Bad ~a)"
    "(tool (bad [value ~a]) (text-result \"bad\"))"
    "(tool (bad) #:output ~a (text-result \"bad\"))"
    "(resource (bad [value ~a]) #:uri \"bad:///{value}\" \"bad\")"
    "(prompt (bad [value ~a]) '())"
    "(shape Bad [value ~a])"
    "(workflow (bad [value ~a]) #:version \"1\" (text-result \"bad\"))"
    "(workflow (bad) #:version \"1\" (checkpoint [value ~a] 1) (text-result \"bad\"))"
    "(workflow (bad) #:version \"1\" (await-input [value ~a] 'request) (text-result \"bad\"))"
    "(workflow (bad) #:version \"1\" (await-input ([value ~a 'request])) (text-result \"bad\"))"
    "(workflow (bad) #:version \"1\" (perform [value ~a] #:adapter save #:policy manual 1) (text-result \"bad\"))"))
(for* ([literal (in-list literals)] [declaration (in-list declarations)])
  (test-case (format "reader schema literal ~a in ~a" literal declaration)
    (define datum (read (open-input-string literal)))
    (define input (open-input-string (string-append "#lang mcp\n" (format declaration literal))))
    (port-count-lines! input)
    (define form (parameterize ([read-accept-reader #t]) (read-syntax 'reader-schema-test input)))
    (check-exn
      (lambda (e)
        (and (exn:fail:syntax? e)
             (for/or ([source (in-list (exn:fail:syntax-exprs e))])
               (and (equal? (syntax->datum source) datum)
                    (equal? (syntax-source source) 'reader-schema-test)
                    (equal? (syntax-line source) 2)))))
      (lambda () (parameterize ([current-namespace (make-base-namespace)]) (expand form))))))
