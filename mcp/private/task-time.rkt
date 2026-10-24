#lang racket/base
(require racket/format "../clock.rkt")
(provide timestamp)
(define (timestamp)
  (define d (seconds->date (mcp-current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~aZ" (~r (date-year d) #:min-width 4 #:pad-string "0")
          (~r (date-month d) #:min-width 2 #:pad-string "0") (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0") (~r (date-minute d) #:min-width 2 #:pad-string "0") (~r (date-second d) #:min-width 2 #:pad-string "0")))
