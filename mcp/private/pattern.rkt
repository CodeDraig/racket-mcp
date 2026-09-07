#lang racket/base
(require racket/string)
(provide schema-pattern)
;; Explicit compatibility translations; unsupported constructs raise errors.
(define (schema-pattern source)
  (define translated
    (for/fold ([s source]) ([entry '(("Letter" . "L") ("Uppercase_Letter" . "Lu")
                                   ("Lowercase_Letter" . "Ll") ("Number" . "N")
                                   ("Decimal_Number" . "Nd") ("Separator" . "Z"))])
      (string-replace s (string-append "{" (car entry) "}") (string-append "{" (cdr entry) "}"))))
  (pregexp translated))
