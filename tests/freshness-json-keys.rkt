#lang racket/base
(require rackunit racket/async-channel mcp mcp/subscription)
(define reads 0)
(define data "old")
;; Non-eq objects and inexact numbers must keep their identity through outbox JSON.
(define dependency (hash 'nested (list (hash 'id 1.0))))
(resource (cached) #:uri "keys:///cached" #:depends-on (list dependency) #:ttl-ms 10000
  (set! reads (add1 reads)) data)
(resource (uncached) #:uri "keys:///uncached" #:depends-on (list dependency) data)
(define store (open-memory-store))
(define rt (make-runtime (make-interface #:resources (list cached uncached)) #:store store))
(define (read who)
  (dispatch rt "resources/read" (hasheq '_meta (request-meta) 'uri "keys:///cached") #:principal who))
(define queue (make-async-channel))
(define listener
  (thread (lambda () (call-with-values
    (lambda () (dispatch rt "subscriptions/listen"
      (hasheq '_meta (request-meta) 'notifications
              (hasheq 'resourceSubscriptions '("keys:///cached" "keys:///uncached")))
      #:principal "alice" #:id 1 #:notify (lambda (m) (async-channel-put queue m)))) void))))
(dynamic-wind void
  (lambda ()
    (check-equal? (hash-ref (sync/timeout 2 queue) 'method) "notifications/subscriptions/acknowledged")
    (void (read "alice")) (void (read "bob"))
    (check-equal? reads 2)
    (set! data "fresh")
    (void (record-committed-change! store "alice" (list dependency)))
    (runtime-drain-changes! rt)
    (check-equal? (hash-ref (car (hash-ref (read "alice") 'contents)) 'text) "fresh")
    (check-equal? reads 3)
    (check-equal? (hash-ref (car (hash-ref (read "bob") 'contents)) 'text) "old")
    (check-equal? reads 3)
    (define notices (for/list ([i (in-range 2)]) (sync/timeout 1 queue)))
    (check-equal? (sort (for/list ([n notices] #:when n) (hash-ref (hash-ref n 'params) 'uri)) string<?)
                  '("keys:///cached" "keys:///uncached"))
    (check-false (sync/timeout 0 queue))
    ;; Also exercise the exported cache primitives without runtime normalization.
    (define cache (make-resource-cache))
    (check-equal? (cache-ref! cache "alice" "one" (list 1.0 dependency) 10000 (lambda () "old")) "old")
    (check-equal? (invalidate-keys! cache (list (string->json (json->string dependency))) #:principal "alice") '("one"))
    (check-equal? (cache-ref! cache "alice" "number" '(1.0) 10000 (lambda () "old")) "old")
    (check-equal? (invalidate-keys! cache '(1) #:principal "alice") '("number")))
  (lambda () (close-subscriptions! (runtime-subscriptions rt)) (thread-wait listener)
    (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))
