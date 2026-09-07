#lang racket/base
(require racket/port racket/string racket/list (prefix-in base: json))
(provide read-json write-json string->json json->string json-null missing missing? json-value? read-json-line)
(define (read-json-line in #:max-bytes [limit 1048576])
  (define out (open-output-bytes))
  (let loop ([count 0])
    (define b (read-byte in))
    (cond [(eof-object? b) (if (zero? count) eof (bytes->string/utf-8 (get-output-bytes out)))]
          [(= b 10) (bytes->string/utf-8 (get-output-bytes out))]
          [(>= count limit) (error 'read-json-line "frame exceeds byte limit")]
          [else (write-byte b out) (loop (add1 count))])))

(define json-null 'null)
(struct absent () #:transparent)
(define missing (absent))
(define missing? absent?)
(define (json-value? v)
  (or (eq? v json-null) (boolean? v) (string? v)
      (and (rational? v) (real? v))
      (and (list? v) (andmap json-value? v))
      (and (hash? v) (for/and ([(k x) (in-hash v)])
                       (and (symbol? k) (json-value? x))))))

;; Numbers are read directly as exact rationals; no binary floating point round trip.
(define (read-json [in (current-input-port)] #:max-bytes [limit 1048576] #:max-depth [depth-limit 128])
  (unless (exact-positive-integer? limit) (raise-argument-error 'read-json "exact-positive-integer?" limit))
  (unless (exact-nonnegative-integer? depth-limit) (raise-argument-error 'read-json "exact-nonnegative-integer?" depth-limit))
  (define count 0)
  ;; Inspect at most four bytes, retaining the port position until consumption.
  ;; read-char would replace malformed UTF-8 with U+FFFD, losing wire validity.
  (define (peek-unit)
    (define first (peek-byte in))
    (cond [(eof-object? first) (values eof 0)]
          [(< first #x80) (values (integer->char first) 1)]
          [else
           (define width (cond [(< first #x80) 1] [(<= #xC2 first #xDF) 2]
                               [(<= #xE0 first #xEF) 3] [(<= #xF0 first #xF4) 4]
                               [else (error 'read-json "invalid UTF-8 leading byte")]))
           (when (> (+ count width) limit) (error 'read-json "input byte limit exceeded"))
           (define raw (peek-bytes width 0 in))
           (unless (= (bytes-length raw) width) (error 'read-json "truncated UTF-8 sequence"))
           (define decoded (bytes->string/utf-8 raw))
           (values (string-ref decoded 0) width)]))
  (define (peek!) (define-values (c width) (peek-unit)) c)
  (define (take!)
    (define-values (c width) (peek-unit))
    (when (> (+ count width) limit) (error 'read-json "input byte limit exceeded"))
    (unless (eof-object? c) (if (= width 1) (read-byte in) (read-bytes width in)) (set! count (+ count width)))
    c)
  (define (white!)
    (let loop () (when (memv (peek!) '(#\space #\tab #\newline #\return)) (take!) (loop))))
  (define (expect! c) (unless (eqv? (take!) c) (error 'read-json "expected ~s" c)))
  (define (str!)
    (define out (open-output-string))
    (write-char (take!) out)
    (let loop ([escape? #f])
      (define c (take!))
      (when (eof-object? c) (error 'read-json "unterminated string"))
      (write-char c out)
      (cond [escape? (loop #f)] [(eqv? c #\\) (loop #t)]
            [(eqv? c #\") (base:string->jsexpr (get-output-string out))]
            [else (loop #f)])))
  (define (value! depth)
    (when (> depth depth-limit) (error 'read-json "nesting limit exceeded"))
    (white!)
    (case (peek!)
      [(#\") (str!)]
      [(#\{)
       (take!) (white!)
       (define h (make-hasheq))
       (unless (eqv? (peek!) #\})
         (let loop ()
           (white!)
           (unless (eqv? (peek!) #\") (error 'read-json "object key must be a string"))
           (define k (string->symbol (str!)))
           (when (hash-has-key? h k) (error 'read-json "duplicate object key: ~a" k))
           (white!) (expect! #\:)
           (hash-set! h k (value! (add1 depth))) (white!)
           (when (eqv? (peek!) #\,) (take!) (loop))))
       (expect! #\}) (make-immutable-hasheq (hash->list h))]
      [(#\[)
       (take!) (white!)
       (define xs
         (if (eqv? (peek!) #\]) '()
             (let loop ([acc '()])
               (define x (value! (add1 depth))) (white!)
               (if (eqv? (peek!) #\,)
                   (begin (take!) (loop (cons x acc))) (reverse (cons x acc))))))
       (expect! #\]) xs]
      [else
       (define token
         (list->string
          (let loop ([acc '()])
            (define c (peek!))
            (if (or (eof-object? c) (memv c '(#\space #\tab #\newline #\return #\, #\] #\})))
                (reverse acc) (loop (cons (take!) acc))))))
       (cond [(equal? token "true") #t] [(equal? token "false") #f]
             [(equal? token "null") json-null]
             [(regexp-match? #px"^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$" token)
              (when (> (string-length token) 4096) (error 'read-json "number too large"))
              (define exp (regexp-match #px"[eE]([+-]?[0-9]+)$" token))
              (when (and exp (> (abs (string->number (cadr exp))) 10000))
                (error 'read-json "number exponent too large"))
              (string->number (string-append "#e" token))]
             [else (error 'read-json "invalid JSON token: ~s" token)])]))
  (value! 0))

(define (string->json str #:max-bytes [limit 1048576])
  (when (> (bytes-length (string->bytes/utf-8 str)) limit) (error 'string->json "input limit exceeded"))
  (define in (open-input-string str))
  (define v (read-json in #:max-bytes limit))
  (unless (regexp-match? #px"^[ \t\r\n]*$" (port->string in)) (error 'string->json "trailing input")) v)

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
