#lang mcp
(module+ test (require rackunit))

(resource (time-snapshot) #:uri "clock:///snapshot" #:ttl-ms 2000
  (number->string (mcp-current-seconds)))

(scenario (cache-expiry session)
  #:interface mcp-interface
  #:clock (make-manual-clock #:seconds 100)
  (define clock (scenario-session-clock session))
  (define (read-time)
    (hash-ref (scenario-call session "resources/read" (hasheq 'uri "clock:///snapshot")) 'result))
  (check-equal? (hash-ref (car (hash-ref (read-time) 'contents)) 'text) "100")
  (void (manual-clock-advance! clock 1))
  (check-equal? (hash-ref (read-time) 'ttlMs) 1000)
  (void (manual-clock-advance! clock 1))
  (check-equal? (hash-ref (car (hash-ref (read-time) 'contents)) 'text) "102"))
