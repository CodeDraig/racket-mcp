#lang racket/base
(require (prefix-in base: json) "json-values.rkt")
(provide write-json json->string)
(define (decimal n)
  (define a (if (exact? n) n (inexact->exact n)))
  (define d (denominator a))
  (define (factor d p) (let loop ([d d] [n 0]) (if (zero? (remainder d p)) (loop (quotient d p) (add1 n)) (values d n))))
  (define-values (d2 twos) (factor d 2))
  (define-values (rest fives) (factor d2 5))
  (unless (= rest 1) (error 'write-json "rational has no finite JSON decimal: ~a" n))
  (define places (max twos fives))
  (define digits (number->string (abs (* (numerator a) (expt 2 (- places twos)) (expt 5 (- places fives))))))
  (define padded (string-append (make-string (max 0 (- (add1 places) (string-length digits))) #\0) digits))
  (string-append (if (negative? a) "-" "")
                 (if (zero? places) padded
                     (string-append (substring padded 0 (- (string-length padded) places)) "."
                                    (substring padded (- (string-length padded) places))))))
(define (write-json v [out (current-output-port)])
  (cond [(string? v) (base:write-json v out)] [(eq? v json-null) (display "null" out)]
        [(boolean? v) (display (if v "true" "false") out)]
        [(rational? v) (display (decimal v) out)]
        [(list? v) (display "[" out) (for ([x (in-list v)] [i (in-naturals)]) (unless (zero? i) (display "," out)) (write-json x out)) (display "]" out)]
        [(hash? v) (display "{" out)
         (for ([k (in-list (sort (hash-keys v) symbol<?))] [i (in-naturals)])
           (unless (zero? i) (display "," out)) (base:write-json (symbol->string k) out) (display ":" out) (write-json (hash-ref v k) out))
         (display "}" out)]
        [else (raise-argument-error 'write-json "json-value?" v)]))
(define (json->string v) (define out (open-output-string)) (write-json v out) (get-output-string out))
