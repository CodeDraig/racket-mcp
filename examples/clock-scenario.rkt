#lang mcp
(module+ test (require rackunit))

(resource (time-snapshot) #:uri "clock:///snapshot" #:ttl-ms 2000
  (number->string (mcp-current-seconds)))

(scenario cache-expiry
  (define clock (make-manual-clock #:seconds 100))
  (define rt (make-runtime mcp-interface #:clock clock))
  (define (read-time)
    (dispatch rt "resources/read"
      (hasheq 'uri "clock:///snapshot" '_meta (request-meta))
      #:principal "scenario-reader"))
  (dynamic-wind void
    (lambda ()
      (check-equal? (hash-ref (car (hash-ref (read-time) 'contents)) 'text) "100")
      (void (manual-clock-advance! clock 1))
      (check-equal? (hash-ref (read-time) 'ttlMs) 1000)
      (void (manual-clock-advance! clock 1))
      (check-equal? (hash-ref (car (hash-ref (read-time) 'contents)) 'text) "102"))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)))))
