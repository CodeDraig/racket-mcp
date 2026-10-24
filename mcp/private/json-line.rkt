#lang racket/base

(provide read-json-line)
(define (read-json-line in #:max-bytes [limit 1048576])
  (define out (open-output-bytes))
  (let loop ([count 0])
    (define b (read-byte in))
    (cond [(eof-object? b) (if (zero? count) eof (bytes->string/utf-8 (get-output-bytes out)))]
          [(= b 10) (bytes->string/utf-8 (get-output-bytes out))]
          [(>= count limit) (error 'read-json-line "frame exceeds byte limit")]
          [else (write-byte b out) (loop (add1 count))])))

