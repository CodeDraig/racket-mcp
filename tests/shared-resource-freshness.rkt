#lang racket/base
(require db rackunit racket/async-channel mcp mcp/subscription)

(test-case "shared committed data fans out explicitly without sharing private cache entries"
  (define store (open-memory-store))
  (define connection (state-store-connection store))
  (query-exec connection "CREATE TABLE documents (body TEXT)")
  (query-exec connection "INSERT INTO documents VALUES ('old')")
  (define owners '("alice" "bob" "charlie"))
  (define reads (make-hash))
  (define revoked '())
  (resource (shared) #:uri "shared:///document" #:depends-on '("document") #:ttl-ms 60000
    (define owner (request-context-principal (current-request-context)))
    (hash-update! reads owner add1 0)
    (string-append owner ":" (query-value connection "SELECT body FROM documents")))
  (define rt
    (make-runtime (make-interface #:resources (list shared)) #:store store
      #:authorize (lambda (principal method params) (not (member principal revoked)))))
  (define (read-as owner)
    (define response (dispatch rt "resources/read"
                       (hasheq '_meta (request-meta) 'uri "shared:///document") #:principal owner))
    (check-equal? (hash-ref response 'cacheScope) "private")
    (hash-ref (car (hash-ref response 'contents)) 'text))
  (define queues (for/hash ([owner owners]) (values owner (make-async-channel))))
  (define workers
    (for/list ([owner owners])
      (thread
        (lambda ()
          (dispatch rt "subscriptions/listen"
            (hasheq '_meta (request-meta) 'notifications
                    (hasheq 'resourceSubscriptions '("shared:///document")))
            #:id owner #:principal owner
            #:notify (lambda (message) (async-channel-put (hash-ref queues owner) message)))))))
  (dynamic-wind void
    (lambda ()
      (for ([owner owners])
        (check-equal? (hash-ref (sync/timeout 5 (hash-ref queues owner)) 'method)
                      "notifications/subscriptions/acknowledged")
        (check-equal? (read-as owner) (string-append owner ":old"))
        (check-equal? (read-as owner) (string-append owner ":old"))
        (check-equal? (hash-ref reads owner) 1))
      (define (commit body fail?)
        (store-transaction store
          (lambda ()
            (query-exec (current-store-connection) "UPDATE documents SET body = ?" body)
            ;; The application's sharing relation supplies owners, including
            ;; revoked owners whose retained private entries must be invalidated.
            (for ([owner owners]) (record-committed-change! store owner '("document")))
            (when fail? (error 'mutation "rollback")))))
      (check-exn #rx"rollback" (lambda () (commit "failed" #t)))
      (runtime-drain-changes! rt)
      (for ([owner owners])
        (check-false (sync/timeout 0 (hash-ref queues owner)))
        (check-equal? (read-as owner) (string-append owner ":old"))
        (check-equal? (hash-ref reads owner) 1))
      (set! revoked '("charlie"))
      (commit "new" #f)
      (runtime-drain-changes! rt)
      (for ([owner '("alice" "bob")])
        (check-equal? (hash-ref (sync/timeout 5 (hash-ref queues owner)) 'method)
                      "notifications/resources/updated")
        (check-equal? (read-as owner) (string-append owner ":new"))
        (check-equal? (hash-ref reads owner) 2))
      (check-false (sync/timeout 0 (hash-ref queues "charlie")))
      (check-exn exn:fail:mcp? (lambda () (read-as "charlie")))
      ;; A later grant cannot revive the revoked owner's old cached body.
      (set! revoked '())
      (check-equal? (read-as "charlie") "charlie:new")
      (check-equal? (hash-ref reads "charlie") 2))
    (lambda ()
      (close-subscriptions! (runtime-subscriptions rt))
      (for-each thread-wait workers)
      (custodian-shutdown-all (runtime-custodian rt))
      (close-store! store))))
