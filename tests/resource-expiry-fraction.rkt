#lang racket/base
(require rackunit mcp mcp/authorization)
(define reads 0)
(resource (child) #:uri "expiry:///child" #:ttl-ms 10000
  (set! reads (add1 reads)) "child")
(resource (parent) #:uri "expiry:///parent" #:ttl-ms 20000
  (text-presentation "parent " (embed (child))))
(for ([offset '(0 50000)])
  (test-case (format "credential deadline with cache clock origin ~a" offset)
    (define clock (make-manual-clock #:seconds 1999/1000))
    (define rt (make-runtime (make-interface #:resources (list child parent)) #:clock clock
      #:cache (make-resource-cache #:clock (lambda () (+ offset (- (clock) 1999))))))
    (define alice (verified-principal "alice" "issuer" "audience" '() 2))
    (define (read uri) (dispatch rt "resources/read" (hasheq '_meta (request-meta) 'uri uri) #:principal alice))
    (dynamic-wind void
      (lambda ()
        (check-equal? (hash-ref (read "expiry:///child") 'ttlMs) 1)
        (check-equal? (hash-ref (read "expiry:///parent") 'ttlMs) 1)
        (check-equal? (hash-ref (read "expiry:///parent") 'ttlMs) 1)
        (void (manual-clock-advance! clock 1/2000))
        (check-equal? (hash-ref (read "expiry:///parent") 'ttlMs) 0)
        (void (manual-clock-advance! clock 1/2000))
        (check-exn exn:fail:mcp? (lambda () (read "expiry:///child")))
        (check-exn exn:fail:mcp? (lambda () (read "expiry:///parent"))))
      (lambda () (custodian-shutdown-all (runtime-custodian rt))))))
