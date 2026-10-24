#lang racket/base
(require racket/list racket/string "../json.rkt" "uri-template-syntax.rkt")
(provide uri-template-expand encode)
(define (encode text allow-reserved?)
  (define out (open-output-string))
  (let loop ([i 0])
    (when (< i (string-length text))
      (define c (string-ref text i))
      (cond [(and allow-reserved? (triplet? text i))
             (display (substring text i (+ i 3)) out) (loop (+ i 3))]
            [else
             (if (or (unreserved? c) (and allow-reserved? (reserved? c)))
                 (write-char c out)
                 (for ([b (in-bytes (string->bytes/utf-8 (string c)))])
                   (define hex (string-upcase (number->string b 16)))
                   (display "%" out) (when (< b 16) (display "0" out)) (display hex out)))
             (loop (add1 i))])))
  (get-output-string out))
(define (undefined? v) (or (missing? v) (eq? v json-null)))
(define (scalar v)
  (cond [(string? v) v]
        [(or (boolean? v) (rational? v)) (json->string v)]
        [else (error 'uri-template "expected a scalar variable value, received ~e" v)]))
(define (prefix-text text limit)
  ;; Count a UTF-8 percent-encoded code point as one character without changing
  ;; its spelling; the expansion operator still decides whether to preserve it.
  (let loop ([i 0] [left limit])
    (cond [(or (zero? left) (= i (string-length text))) (substring text 0 i)]
          [else
           (define width
             (cond [(triplet? text i)
                    (define first (string->number (substring text (add1 i) (+ i 3)) 16))
                    (define count (cond [(<= #xC2 first #xDF) 2] [(<= #xE0 first #xEF) 3]
                                        [(<= #xF0 first #xF4) 4] [else 1]))
                    (define bytes-value
                      (and (for/and ([offset (in-range count)]) (triplet? text (+ i (* offset 3))))
                           (list->bytes (for/list ([offset (in-range count)])
                                          (define start (+ i (* offset 3)))
                                          (string->number (substring text (add1 start) (+ start 3)) 16)))))
                    (if (and bytes-value (with-handlers ([exn:fail? (lambda (_) #f)])
                                           (= (string-length (bytes->string/utf-8 bytes-value #f)) 1)))
                        (* count 3) 3)]
                   [else 1]))
           (loop (+ i width) (sub1 left))])))
(define (expand-expression part env)
  (define op (expression-operator part))
  (define allow-reserved? (memv op '(#\+ #\#)))
  (define named? (memv op '(#\; #\? #\&)))
  (define query? (memv op '(#\? #\&)))
  (define separator (case op [(#\.) "."] [(#\/) "/"] [(#\;) ";"] [(#\? #\&) "&"] [else ","]))
  (define (enc v) (encode (scalar v) allow-reserved?))
  (define (pair-text key value)
    (string-append key (if (and (string=? value "") (not query?)) "" (string-append "=" value))))
  (define pieces
    (append-map
     (lambda (var)
       (define name (symbol->string (variable-name var)))
       (define value (hash-ref env (variable-name var) missing))
       (define (named text) (if named? (pair-text name text) text))
       (cond [(undefined? value) '()]
             [(or (list? value) (hash? value))
              (when (variable-prefix var) (error 'uri-template "prefix modifier cannot apply to a composite value"))
              (cond [(list? value)
                     (define members (filter (lambda (v) (not (undefined? v))) value))
                     (cond [(null? members) '()]
                           [(variable-explode? var) (map (lambda (v) (named (enc v))) members)]
                           [else (list (named (string-join (map enc members) ",")))])]
                    [else
                     (unless (andmap symbol? (hash-keys value)) (error 'uri-template "map keys must be symbols"))
                     (define pairs (sort (filter (lambda (p) (not (undefined? (cdr p)))) (hash->list value)) symbol<? #:key car))
                     (cond [(null? pairs) '()]
                           [(variable-explode? var)
                            (for/list ([p (in-list pairs)]) (pair-text (enc (symbol->string (car p))) (enc (cdr p))))]
                           [else (list (named (string-join (append-map (lambda (p) (list (enc (symbol->string (car p))) (enc (cdr p)))) pairs) ",")))])])]
             [else
              (define text (scalar value))
              (define prefix (variable-prefix var))
              (list (named (enc (if prefix (prefix-text text prefix) text))))]))
     (expression-variables part)))
  (if (null? pieces) ""
      (string-append (case op [(#\#) "#"] [(#\.) "."] [(#\/) "/"] [(#\;) ";"] [(#\?) "?"] [(#\&) "&"] [else ""])
                     (string-join pieces separator))))
(define (uri-template-expand template env)
  (unless (hash? env) (raise-argument-error 'uri-template-expand "hash?" env))
  (apply string-append
    (for/list ([part (in-list (parse-template template))])
      (if (string? part) (encode part #t) (expand-expression part env)))))
