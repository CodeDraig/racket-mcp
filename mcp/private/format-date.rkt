#lang racket/base

(provide date-parts timestamp?)
(define (leap-year? year)
  (and (zero? (modulo year 4))
       (or (not (zero? (modulo year 100))) (zero? (modulo year 400)))))
(define (month-days year month)
  (if (and (= month 2) (leap-year? year)) 29
      (vector-ref '#(0 31 28 31 30 31 30 31 31 30 31 30 31) month)))
(define (date-parts value)
  (define found (regexp-match #px"^([0-9]{4})-([0-9]{2})-([0-9]{2})$" value))
  (and found
       (let* ([parts (map string->number (cdr found))]
              [year (car parts)] [month (cadr parts)] [day (caddr parts)])
         (and (<= 1 month 12) (<= 1 day (month-days year month)) parts))))
(define (timestamp? value)
  (define found
    (regexp-match #px"^([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.][0-9]+)?([Zz]|([+-])([0-9]{2}):([0-9]{2}))$" value))
  (and found
       (let ([date (date-parts (list-ref found 1))]
             [hour (string->number (list-ref found 2))]
             [minute (string->number (list-ref found 3))]
             [second (string->number (list-ref found 4))]
             [offset-hour (if (list-ref found 7) (string->number (list-ref found 7)) 0)]
             [offset-minute (if (list-ref found 8) (string->number (list-ref found 8)) 0)])
         (and date (< hour 24) (< minute 60) (<= second 60)
              (< offset-hour 24) (< offset-minute 60)
              (or (< second 60)
                  ;; Leap seconds occur at a UTC month-end, regardless of the
                  ;; written offset. This checks the possible position, not an
                  ;; external historical/predicted leap-second bulletin.
                  (let* ([offset (* (if (equal? (list-ref found 6) "-") -1 1)
                                    (+ (* 60 offset-hour) offset-minute))]
                         [utc-minute (- (+ (* 60 hour) minute) offset)]
                         [utc-day (+ (caddr date) (floor (/ utc-minute 1440)))])
                    (and (= (modulo utc-minute 1440) 1439)
                         (or (= utc-day 0)
                             (= utc-day (month-days (car date) (cadr date)))))))))))

