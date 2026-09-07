#lang racket/base
(require racket/string racket/list net/uri-codec "json.rkt")
(provide uri-template-expand uri-template-matcher)
(define (encode s reserved?)
  (apply string-append
    (for/list ([b (in-bytes (string->bytes/utf-8 s))])
      (define c (integer->char b))
      (if (or (<= 65 b 90) (<= 97 b 122) (<= 48 b 57) (memv c '(#\- #\. #\_ #\~))
              (and reserved? (string-contains? ":/?#[]@!$&'()*+,;=" (string c)))) (string c)
          (let ([n (string-upcase (number->string b 16))]) (string-append "%" (if (= 1 (string-length n)) "0" "") n))))))
(define (uri-template-expand template env)
  (regexp-replace* #px"\\{([^{}]+)\\}" template
    (lambda (whole expression)
      (define op (and (memv (string-ref expression 0) '(#\+ #\# #\. #\/ #\; #\? #\&)) (string-ref expression 0)))
      (define vars (string-split (if op (substring expression 1) expression) ","))
      (define reserved? (memv op '(#\+ #\#)))
      (define named? (memv op '(#\; #\? #\&)))
      (define separator (case op [(#\.) "."] [(#\/) "/"] [(#\;) ";"] [(#\? #\&) "&"] [else ","]))
      (define pieces
        (append-map
          (lambda (var)
            (define explode? (string-suffix? var "*"))
            (define prefix-parts (string-split (if explode? (substring var 0 (sub1 (string-length var))) var) ":"))
            (define name (car prefix-parts))
            (define value (hash-ref env (string->symbol name) missing))
            (define (enc x) (encode (if (string? x) x (json->string x)) reserved?))
            (define (named x [key name]) (if named? (string-append (enc key) (if (and (equal? x "") (eqv? op #\;)) "" "=") x) x))
            (cond [(or (missing? value) (eq? value json-null)) '()]
                  [(list? value) (if (null? value) '() (if explode? (map (lambda (v) (named (enc v))) value) (list (named (string-join (map enc value) ",")))))]
                  [(hash? value)
                   (define pairs (sort (hash->list value) symbol<? #:key car))
                   (cond [(null? pairs) '()]
                         [explode? (for/list ([p (in-list pairs)]) (string-append (enc (symbol->string (car p))) "=" (enc (cdr p))))]
                         [else (list (named (string-join (append-map (lambda (p) (list (enc (symbol->string (car p))) (enc (cdr p)))) pairs) ",")))])]
                  [else (define s (if (string? value) value (json->string value)))
                        (define text (if (pair? (cdr prefix-parts)) (substring s 0 (min (string-length s) (or (string->number (cadr prefix-parts)) (error 'uri-template "invalid prefix")))) s))
                        (list (named (enc text)))])) vars))
      (if (null? pieces) "" (string-append (case op [(#\#) "#"] [(#\.) "."] [(#\/) "/"] [(#\;) ";"] [(#\?) "?"] [(#\&) "&"] [else ""]) (string-join pieces separator))))))
(define (uri-template-matcher template)
  (define matches (regexp-match-positions* #px"\\{[A-Za-z_][A-Za-z_0-9]*\\}" template))
  (define names '()) (define end 0)
  (define fragments
    (for/list ([m (in-list matches)])
      (when (and (> end 0) (= end (car m))) (error 'uri-template-matcher "adjacent variables require an explicit matcher"))
      (define literal (substring template end (car m)))
      (when (and (> end 0) (not (regexp-match? #px"[/?#:&=]" literal)))
        (error 'uri-template-matcher "variables separated only by unreserved characters require an explicit matcher"))
      (define name (string->symbol (substring template (add1 (car m)) (sub1 (cdr m)))))
      (when (memq name names) (error 'uri-template-matcher "repeated variables require an explicit matcher"))
      (set! names (append names (list name))) (set! end (cdr m))
      (string-append (regexp-quote literal) "([^/?#]*)")))
  (define tail (substring template end))
  (when (or (string-contains? tail "{") (for/or ([f (in-list fragments)]) (string-contains? f "\\{")))
    (error 'uri-template-matcher "complex template requires an explicit matcher"))
  (define pattern (pregexp (string-append "^" (apply string-append fragments) (regexp-quote tail) "$")))
  (lambda (uri) (define m (regexp-match pattern uri))
    (and m (for/hasheq ([name (in-list names)] [value (in-list (cdr m))]) (values name (uri-decode value))))))
