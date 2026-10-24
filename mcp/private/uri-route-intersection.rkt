#lang racket/base
(require racket/list "uri-template-syntax.rkt")
(provide generated-matcher uri-tokens uri-matchers-overlap)
;; A URI is tokenized into literal characters and complete percent triplets.
;; UTF-8 validity is a finite-state condition on percent-encoded bytes. This
;; keeps intersection exact without enumerating strings or invoking handlers.
(define (uri-tokens text)
  (let loop ([i 0] [out '()])
    (if (= i (string-length text)) (reverse out)
        (let ([end (+ i (if (triplet? text i) 3 1))])
          (loop end (cons (substring text i end) out))))))
(define (utf8-next state byte)
  (case state
    [(0) (cond [(<= byte #x7F) 0] [(<= #xC2 byte #xDF) 1]
               [(= byte #xE0) 4] [(= byte #xED) 5] [(<= #xE1 byte #xEF) 2]
               [(= byte #xF0) 6] [(= byte #xF4) 7] [(<= #xF1 byte #xF3) 3] [else #f])]
    [(1 2 3) (and (<= #x80 byte #xBF) (sub1 state))]
    [(4) (and (<= #xA0 byte #xBF) 1)]
    [(5) (and (<= #x80 byte #x9F) 1)]
    [(6) (and (<= #x90 byte #xBF) 2)]
    [(7) (and (<= #x80 byte #x8F) 2)]))
(struct generated-matcher (procedure tokens)
  #:property prop:procedure (struct-field-index procedure))
(define (machine-closure tokens states)
  (sort (remove-duplicates
    (append-map
     (lambda (state)
       (let loop ([state state])
         (define position (quotient state 8))
         (if (and (zero? (remainder state 8)) (< position (vector-length tokens))
                  (not (vector-ref tokens position)))
             (cons state (loop (+ state 8))) (list state)))) states)) <))
(define (machine-step tokens states token)
  (machine-closure tokens
   (filter values
    (for/list ([state (in-list states)])
      (define position (quotient state 8))
      (define utf8 (remainder state 8))
      (and (< position (vector-length tokens))
           (let ([expected (vector-ref tokens position)])
             (cond [expected (and (string=? expected token) (* 8 (add1 position)))]
                   [else
                    (define next
                      (if (triplet? token 0)
                          (utf8-next utf8 (string->number (substring token 1) 16))
                          (and (zero? utf8) (= (string-length token) 1)
                               (unreserved? (string-ref token 0)) 0)))
                    (and next (+ (* position 8) next))])))))))
(define percent-alphabet
  (for/list ([byte (in-range 256)])
    (string-append "%" (if (< byte 16) "0" "") (string-upcase (number->string byte 16)))))
(define (uri-matchers-overlap left right #:max-states [limit 10000])
  (unless (exact-positive-integer? limit) (raise-argument-error 'uri-matchers-overlap "exact-positive-integer?" limit))
  (cond [(not (and (generated-matcher? left) (generated-matcher? right))) 'unknown]
        [else
         (define a (generated-matcher-tokens left))
         (define b (generated-matcher-tokens right))
         (define alphabet (remove-duplicates (append (filter values (vector->list a))
                                                    (filter values (vector->list b)) '("a") percent-alphabet)))
         (define initial (cons (machine-closure a '(0)) (machine-closure b '(0))))
         (define predecessors (make-hash (list (cons initial #f))))
         (define (witness state [out '()])
           (define edge (hash-ref predecessors state))
           (if edge (witness (car edge) (cons (cdr edge) out)) (apply string-append out)))
         (let search ([front (list initial)] [back '()])
           (cond [(null? front) (if (null? back) #f (search (reverse back) '()))]
                 [else
                  (define state (car front))
                  (cond [(and (member (* 8 (vector-length a)) (car state))
                              (member (* 8 (vector-length b)) (cdr state))) (witness state)]
                        [else
                         (define next-back
                           (for/fold ([back back]) ([token (in-list alphabet)])
                             (define next-a (machine-step a (car state) token))
                             (define next-b (if (null? next-a) '() (machine-step b (cdr state) token)))
                             (define next (cons next-a next-b))
                             (cond [(or (null? next-a) (null? next-b) (hash-has-key? predecessors next)) back]
                                   [else
                                    (when (>= (hash-count predecessors) limit)
                                      (error 'uri-matchers-overlap "URI overlap analysis state limit exceeded"))
                                    (hash-set! predecessors next (cons state token))
                                    (cons next back)])))
                         (search (cdr front) next-back)])]))]))
