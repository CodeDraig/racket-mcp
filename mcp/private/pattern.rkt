#lang racket/base
(require racket/string racket/list)
(provide schema-pattern)

;; A Unicode-aware compatibility frontend, not a complete ECMAScript engine.
;; Unsupported features fail rather than acquiring Racket-only meanings.
;; https://tc39.es/ecma262/multipage/text-processing.html#sec-patterns
(define properties
  (hash "Letter" "L" "Uppercase_Letter" "Lu" "Lowercase_Letter" "Ll"
        "Number" "N" "Decimal_Number" "Nd" "digit" "Nd" "Separator" "Z"))
(define whitespace '(9 10 11 12 13 32 160 5760 8192 8193 8194 8195 8196 8197 8198 8199 8200 8201 8202 8232 8233 8239 8287 12288 65279))
(define any-character "[\\s\\S]")
(define whitespace-pattern (string-append "[" (list->string (map integer->char whitespace)) "]"))
(define (complement pattern)
  ;; Assertions and consumption form one atom: a following quantifier must
  ;; recheck the exclusion on every character, including zero repetitions.
  (string-append "(?:(?!(?:" pattern "))" any-character ")"))
(define (union patterns)
  ;; Keep a consuming width even for the empty character set. A bare failing
  ;; assertion makes Racket reject otherwise valid quantifiers such as []*.
  (if (null? patterns) (string-append "(?:(?!)" any-character ")")
      (string-append "(?:" (string-join patterns "|") ")")))
(define (class-char n)
  (define c (integer->char n))
  (if (memv c '(#\\ #\[ #\] #\- #\^)) (string #\\ c) (string c)))
(struct atom (pattern scalar) #:transparent)

(define (schema-pattern source)
  (unless (string? source) (raise-argument-error 'schema-pattern "string?" source))
  (define size (string-length source))
  (define out (open-output-string))
  (define (at i) (and (< i size) (string-ref source i)))
  (define (bad i message) (error 'schema-pattern "~a at character ~a in ~s" message i source))
  (define (literal n position)
    (when (or (> n #x10ffff) (<= #xd800 n #xdfff))
      (bad position "unsupported non-scalar Unicode escape"))
    (atom (regexp-quote (string (integer->char n))) n))
  (define (hex start end)
    (unless (and (<= end size) (< start end)
                 (regexp-match? #px"^[0-9A-Fa-f]+$" (substring source start end)))
      (bad start "invalid hexadecimal escape"))
    (string->number (substring source start end) 16))
  (define (escaped i in-class?)
    (define c (at (add1 i)))
    (unless c (bad i "unfinished escape"))
    (define after (+ i 2))
    (cond
      [(assv c '((#\t . 9) (#\n . 10) (#\v . 11) (#\f . 12) (#\r . 13)))
       => (lambda (entry) (values (literal (cdr entry) i) after))]
      [(eqv? c #\c)
       (define letter (at after))
       (unless (and letter (or (char<=? #\A letter #\Z) (char<=? #\a letter #\z)))
         (bad i "control escape requires an ASCII letter"))
       (values (literal (modulo (char->integer letter) 32) i) (add1 after))]
      [(eqv? c #\x) (values (literal (hex after (+ after 2)) i) (+ after 2))]
      [(eqv? c #\u)
       (cond
         [(eqv? (at after) #\{)
          (define end (for/first ([j (in-range (add1 after) size)] #:when (eqv? (at j) #\})) j))
          (unless end (bad i "unfinished Unicode escape"))
          (values (literal (hex (add1 after) end) i) (add1 end))]
         [else
          (define n (hex after (+ after 4)))
          (define next (+ after 4))
          (cond
            [(and (<= #xd800 n #xdbff) (eqv? (at next) #\\) (eqv? (at (add1 next)) #\u))
             (define low (hex (+ next 2) (+ next 6)))
             (unless (<= #xdc00 low #xdfff) (bad i "invalid Unicode surrogate pair"))
             (values (literal (+ #x10000 (* (- n #xd800) #x400) (- low #xdc00)) i) (+ next 6))]
            [else (values (literal n i) next)])])]
      [(memv c '(#\s #\S))
       (values (atom (if (eqv? c #\s) whitespace-pattern (complement whitespace-pattern)) #f) after)]
      [(memv c '(#\p #\P))
       (unless (eqv? (at after) #\{) (bad i "property escape requires braces"))
       (define end (for/first ([j (in-range (add1 after) size)] #:when (eqv? (at j) #\})) j))
       (unless end (bad i "unfinished property escape"))
       (define property (substring source (add1 after) end))
       (unless (regexp-match? #px"^[A-Za-z_]+$" property) (bad i "unsupported Unicode property"))
       (values (atom (string-append (string #\\ c) "{" (hash-ref properties property property) "}") #f) (add1 end))]
      [(and in-class? (eqv? c #\b)) (values (literal 8 i) after)]
      [(eqv? c #\0)
       (when (and (at after) (char-numeric? (at after))) (bad i "legacy octal escapes are unsupported"))
       (values (literal 0 i) after)]
      [(char<=? #\1 c #\9) (bad i "backreferences are unsupported")]
      [(or (memv c '(#\d #\D #\w #\W)) (and (not in-class?) (memv c '(#\b #\B))))
       (values (atom (string #\\ c) #f) after)]
      [(or (memv c '(#\^ #\$ #\\ #\. #\* #\+ #\? #\( #\) #\[ #\] #\{ #\} #\| #\/))
           (and in-class? (eqv? c #\-)))
       (values (literal (char->integer c) i) after)]
      [else (bad i "unsupported escape")]))
  (define (range-pattern lower upper position)
    (unless (<= lower upper) (bad position "reversed character range"))
    ;; Racket 9.2/9.3 miscompile some Unicode ranges crossing UTF-8 suffix
    ;; boundaries (e.g. FF00-FFFF excludes FF40). Each emitted interval stays
    ;; within one final-byte block; an atomic wrapper prevents the optimizer
    ;; from merging adjacent intervals back into the defective wide range.
    ;; Each interval consumes one character, so this removes no useful choices.
    ;; Surrogate-only intervals are omitted.
    (union
     (let loop ([start lower])
       (cond [(> start upper) '()]
             [else
              (define end (min upper (+ start (- 63 (modulo start 64)))))
              (define tail (loop (add1 end)))
              (if (<= #xd800 start #xdfff) tail
                  (cons (if (= start end) (atom-pattern (literal start position))
                            (string-append "(?>[" (class-char start) "-" (class-char end) "])")) tail))]))))
  (define (character-class i)
    (define negative? (eqv? (at (add1 i)) #\^))
    (define-values (tokens end)
      (let loop ([j (+ i (if negative? 2 1))] [items '()])
        (define c (at j))
        (unless c (bad i "unfinished character class"))
        (cond [(eqv? c #\]) (values (reverse items) (add1 j))]
              [(eqv? c #\\)
               (define-values (item next) (escaped j #t))
               (loop next (cons item items))]
              [else (loop (add1 j) (cons (if (eqv? c #\-) 'dash (literal (char->integer c) j)) items))])))
    (define pieces
      (let loop ([items tokens])
        (cond [(null? items) '()]
              [(and (atom? (car items)) (pair? (cdr items)) (eq? (cadr items) 'dash) (pair? (cddr items)))
               (define right (caddr items))
               (unless (and (atom-scalar (car items)) (or (eq? right 'dash) (atom-scalar right)))
                 (bad i "character-class escape cannot be a range endpoint"))
               (cons (range-pattern (atom-scalar (car items)) (if (eq? right 'dash) 45 (atom-scalar right)) i)
                     (loop (cdddr items)))]
              [else (cons (if (eq? (car items) 'dash) "-" (atom-pattern (car items))) (loop (cdr items)))])))
    (define pattern (union pieces))
    (values (if negative? (complement pattern) pattern) end))
  (let loop ([i 0])
    (when (< i size)
      (define c (at i))
      (cond
        [(eqv? c #\\)
         (define-values (item next) (escaped i #f))
         (display (atom-pattern item) out) (loop next)]
        [(eqv? c #\[)
         (define-values (pattern next) (character-class i))
         (display pattern out) (loop next)]
        [(eqv? c #\]) (bad i "unmatched closing bracket")]
        [(eqv? c #\.) (display (complement "[\n\r\u2028\u2029]") out) (loop (add1 i))]
        [(eqv? c #\{)
         (define matched (regexp-match-positions #px"\\{[0-9]+(?:,[0-9]*)?\\}" source i))
         (unless (and matched (= (caar matched) i)) (bad i "invalid repetition quantifier"))
         (display (substring source i (cdar matched)) out) (loop (cdar matched))]
        [(eqv? c #\}) (bad i "unmatched closing brace")]
        [(and (eqv? c #\() (eqv? (at (add1 i)) #\?)
              (not (or (memv (at (+ i 2)) '(#\: #\= #\!))
                       (and (eqv? (at (+ i 2)) #\<) (memv (at (+ i 3)) '(#\= #\!))))))
         (bad i "unsupported group construct")]
        [else (display c out) (loop (add1 i))])))
  (pregexp (get-output-string out)))
