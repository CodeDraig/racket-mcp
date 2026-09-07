#lang racket/base
(require rackunit racket/file db mcp)
(define (bounded thunk)
  (define result (box #f))
  (define worker (thread (lambda () (set-box! result (with-handlers ([(lambda (_) #t) (lambda (e) (cons #f e))]) (cons #t (thunk)))))))
  (unless (sync/timeout 5 worker) (kill-thread worker) (error 'test "store did not become reusable"))
  (define value (unbox result))
  (if (car value) (cdr value) (raise (cdr value))))
(define path (make-temporary-file "mcp-terminated-~a.sqlite"))
(dynamic-wind void
  (lambda ()
    (for ([store (in-list (list (open-memory-store) (open-sqlite-store path)))])
      (define connection (state-store-connection store))
      (query-exec connection "CREATE TABLE mutation(value TEXT)")
      (dynamic-wind void
        (lambda ()
          (for ([mode '(kill custodian break escape abort)])
            (define entered (make-semaphore 0))
            (define owner (make-custodian))
            (define worker
              (parameterize ([current-custodian owner])
                (thread
                 (lambda ()
                   (define mine (current-thread))
                   (with-handlers ([exn:break? void])
                     (let/ec leave
                       (call-with-continuation-prompt
                        (lambda ()
                          (store-transaction store
                            (lambda ()
                              (check-eq? (current-thread) mine)
                              (start-transaction connection)
                              (query-exec connection "INSERT INTO mutation VALUES ('abandoned')")
                              (semaphore-post entered)
                              (case mode
                                [(escape) (leave 'escaped)]
                                [(abort) (abort-current-continuation (default-continuation-prompt-tag) void)]
                                [else (sync never-evt)])))))))))))
            (check-not-false (sync/timeout 5 entered))
            (case mode [(kill) (kill-thread worker)] [(custodian) (custodian-shutdown-all owner)] [(break) (break-thread worker)])
            (check-not-false (sync/timeout 5 worker))
            (check-equal? (bounded (lambda () (store-transaction store (lambda () (query-value connection "SELECT count(*) FROM mutation"))))) 0)
            (check-false (in-transaction? connection))
            (custodian-shutdown-all owner))
          ;; Child threads inherit parameters but do not inherit transaction ownership.
          (define attempting (make-semaphore 0))
          (define child-entered (make-semaphore 0))
          (define child #f)
          (store-transaction store
            (lambda ()
              (set! child (thread (lambda () (semaphore-post attempting)
                                   (store-transaction store (lambda () (semaphore-post child-entered))))))
              (check-not-false (sync/timeout 5 attempting))
              (check-false (sync/timeout 0.05 child-entered))))
          (check-not-false (sync/timeout 5 child-entered))
          (check-not-false (sync/timeout 5 child))
          (define waiting (make-semaphore 0))
          (define cancelled #f)
          (store-transaction store
            (lambda ()
              (set! cancelled
                (thread (lambda ()
                          (with-handlers ([exn:break? void])
                            (semaphore-post waiting)
                            (store-transaction store (lambda () (error 'test "cancelled waiter executed")))))))
              (check-not-false (sync/timeout 5 waiting))
              (break-thread cancelled)
              (check-not-false (sync/timeout 5 cancelled))))
          ;; The application cannot commit the SDK's managed transaction early.
          (check-exn exn:fail?
            (lambda () (store-transaction store (lambda () (query-exec connection "INSERT INTO mutation VALUES ('early')") (commit-transaction connection)))))
          (check-equal? (bounded (lambda () (store-transaction store (lambda () (query-value connection "SELECT count(*) FROM mutation"))))) 0)
          (check-equal?
           (call-with-values
            (lambda () (store-transaction store
                         (lambda () (call-with-transaction connection (lambda () (query-exec connection "INSERT INTO mutation VALUES ('committed')")))
                                    (values 1 #f)))) list)
           '(1 #f)))
        (lambda () (close-store! store))))
    (define reopened (open-sqlite-store path))
    (check-equal? (query-list (state-store-connection reopened) "SELECT value FROM mutation") '("committed"))
    (close-store! reopened))
  (lambda () (delete-file path)))
