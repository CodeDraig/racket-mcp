#lang racket/base
(require racket/list
         "uri-template-syntax.rkt"
         "uri-template-expansion.rkt"
         "uri-route-intersection.rkt")
(provide uri-template-matcher)
(define (decode-simple text)
  (define out (open-output-bytes))
  (let loop ([i 0])
    (when (< i (string-length text))
      (if (triplet? text i)
          (begin (write-byte (string->number (substring text (add1 i) (+ i 3)) 16) out) (loop (+ i 3)))
          (begin (write-byte (char->integer (string-ref text i)) out) (loop (add1 i))))))
  (bytes->string/utf-8 (get-output-bytes out) #f))
(define (uri-template-matcher template)
  (define parts (parse-template template))
  (define names '())
  (define separator "")
  (define fragments
    (for/list ([part (in-list parts)])
      (cond [(string? part) (set! separator (string-append separator (encode part #t))) (regexp-quote (encode part #t))]
            [else
             (unless (and (not (expression-operator part)) (= (length (expression-variables part)) 1)
                          (not (variable-prefix (car (expression-variables part))))
                          (not (variable-explode? (car (expression-variables part)))))
               (error 'uri-template-matcher "complex template requires an explicit matcher"))
             (when (and (pair? names) (not (for/or ([c (in-string separator)]) (reserved? c))))
               (error 'uri-template-matcher "adjacent or ambiguously separated variables require an explicit matcher"))
             (define name (variable-name (car (expression-variables part))))
             (when (memq name names) (error 'uri-template-matcher "repeated variables require an explicit matcher"))
             (set! names (append names (list name))) (set! separator "")
             "((?:[A-Za-z0-9._~-]|%[0-9A-Fa-f]{2})*)"])))
  (define pattern (pregexp (string-append "^" (apply string-append fragments) "$")))
  (generated-matcher
   (lambda (uri)
     (define m (and (string? uri) (regexp-match pattern uri)))
     (and m (with-handlers ([exn:fail? (lambda (_) #f)])
              (for/hasheq ([name (in-list names)] [value (in-list (cdr m))]) (values name (decode-simple value))))))
   (list->vector (append-map (lambda (part) (if (string? part) (uri-tokens (encode part #t)) (list #f))) parts))))

