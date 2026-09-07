#lang racket/base
(require racket/string)
(provide make-sse-reader read-sse-event (struct-out sse-event))
(struct sse-event (type data) #:transparent)
(struct sse-reader (input limit skip-lf? first?) #:mutable)
(define (make-sse-reader input #:max-bytes [limit 1048576])
  (unless (exact-positive-integer? limit) (raise-argument-error 'make-sse-reader "exact-positive-integer?" limit))
  (sse-reader input limit #f #t))
;; Count bytes before decoding or retaining a line. CR ends a line immediately;
;; a following LF is consumed on the next read, including across packet splits.
(define (read-line/bounded reader remaining)
  (define in (sse-reader-input reader))
  (define out (open-output-bytes))
  (let loop ([count 0])
    (define b (read-byte in))
    (cond [(and (sse-reader-skip-lf? reader) (begin (set-sse-reader-skip-lf?! reader #f) (eqv? b 10))) (loop count)]
          [(eof-object? b) (values eof count)]
          [else
           (when (>= count remaining) (error 'sse "SSE event byte limit exceeded"))
           (cond [(or (= b 10) (= b 13))
                  (when (= b 13) (set-sse-reader-skip-lf?! reader #t))
                  (values (bytes->string/utf-8 (get-output-bytes out)) (add1 count))]
                 [else (write-byte b out) (loop (add1 count))])])) )
(define (read-sse-event reader)
  (let loop ([data '()] [type "message"] [size 0])
    (define-values (raw bytes) (read-line/bounded reader (- (sse-reader-limit reader) size)))
    (define line
      (if (and (sse-reader-first? reader) (not (eof-object? raw)))
          (begin (set-sse-reader-first?! reader #f)
                 (if (string-prefix? raw "\uFEFF") (substring raw 1) raw)) raw))
    (cond [(eof-object? line) eof] ; An unterminated event is never dispatched.
          [(equal? line "")
           (if (null? data) (loop '() "message" 0)
               (sse-event (if (equal? type "") "message" type) (string-join (reverse data) "\n")))]
          [else
           (define colon (for/first ([ch (in-string line)] [i (in-naturals)] #:when (char=? ch #\:)) i))
           (define field (if colon (substring line 0 colon) line))
           (define value (if colon (substring line (add1 colon)) ""))
           ;; SSE removes exactly one ASCII space, not arbitrary whitespace.
           (define trimmed (if (string-prefix? value " ") (substring value 1) value))
           (loop (if (equal? field "data") (cons trimmed data) data)
                 (if (equal? field "event") trimmed type) (+ size bytes))])))
