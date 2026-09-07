#lang racket/base
(require racket/string racket/list "json.rkt")
(provide uri-template-expand uri-template-matcher check-uri-template! uri-template-variables)
(struct variable (name explode? prefix) #:transparent)
(struct expression (operator variables) #:transparent)
(define varspec-pattern #px"^((?:[A-Za-z0-9_]|%[0-9A-Fa-f]{2})(?:\\.?(?:[A-Za-z0-9_]|%[0-9A-Fa-f]{2}))*)(?:(\\*)|:([1-9][0-9]{0,3}))?$")
(define (triplet? text i)
  (and (<= (+ i 3) (string-length text)) (char=? (string-ref text i) #\%)
       (for/and ([j (in-range (add1 i) (+ i 3))])
         (define c (string-ref text j))
         (or (char<=? #\0 c #\9) (char<=? #\a c #\f) (char<=? #\A c #\F)))))
(define (unreserved? c)
  (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char<=? #\0 c #\9)
      (memv c '(#\- #\. #\_ #\~))))
(define (reserved? c) (string-contains? ":/?#[]@!$&'()*+,;=" (string c)))
(define (unicode-literal? n)
  (or (<= #xA0 n #xD7FF) (<= #xE000 n #xFDCF) (<= #xFDF0 n #xFFEF)
      (and (<= #x10000 n #x10FFFD) (<= (bitwise-and n #xFFFF) #xFFFD)
           (not (<= #xE0000 n #xE0FFF)))))
(define (literal? c)
  (define n (char->integer c))
  ;; RFC 6570 verified erratum 6937 admits apostrophes in literals.
  (or (= n #x21) (<= #x23 n #x24) (<= #x26 n #x3B)
      (= n #x3D) (<= #x3F n #x5B) (= n #x5D) (= n #x5F)
      (<= #x61 n #x7A) (= n #x7E) (unicode-literal? n)))
(define (parse-template template)
  (unless (string? template) (raise-argument-error 'uri-template "string?" template))
  (define size (string-length template))
  (let loop ([i 0] [start 0] [out '()])
    (cond [(= i size) (reverse (if (< start i) (cons (substring template start i) out) out))]
          [(char=? (string-ref template i) #\{)
           (define end (for/first ([j (in-range (add1 i) size)] #:when (char=? (string-ref template j) #\})) j))
           (unless end (error 'uri-template "unclosed expression at ~a" i))
           (define body (substring template (add1 i) end))
           (when (string=? body "") (error 'uri-template "empty expression at ~a" i))
           (define operator (and (memv (string-ref body 0) '(#\+ #\# #\. #\/ #\; #\? #\&)) (string-ref body 0)))
           (define variables
             (for/list ([part (in-list (string-split (if operator (substring body 1) body) "," #:trim? #f))])
               (define m (regexp-match varspec-pattern part))
               (unless m (error 'uri-template "invalid or unsupported variable expression: ~a" part))
               (variable (string->symbol (cadr m)) (and (caddr m) #t) (and (cadddr m) (string->number (cadddr m))))))
           (loop (add1 end) (add1 end)
                 (cons (expression operator variables) (if (< start i) (cons (substring template start i) out) out)))]
          [(triplet? template i) (loop (+ i 3) start out)]
          [(literal? (string-ref template i)) (loop (add1 i) start out)]
          [else (error 'uri-template "invalid literal character at ~a" i)])))
(define (check-uri-template! template) (parse-template template) template)
(define (uri-template-variables template)
  (remove-duplicates
   (append-map (lambda (part) (if (expression? part) (map variable-name (expression-variables part)) '())) (parse-template template))))
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
  (lambda (uri)
    (define m (and (string? uri) (regexp-match pattern uri)))
    (and m (with-handlers ([exn:fail? (lambda (_) #f)])
             (for/hasheq ([name (in-list names)] [value (in-list (cdr m))]) (values name (decode-simple value)))))))
