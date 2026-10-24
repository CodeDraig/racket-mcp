#lang racket/base
(require racket/port (prefix-in base: json) "json-values.rkt")
(provide read-json string->json)
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

