#lang racket/base
(require db racket/random racket/list "json.rkt")
(provide open-sqlite-store open-memory-store close-store! store-transaction
         (struct-out state-store) (struct-out stored-instance)
         create-instance! load-instance list-instances update-instance! record-event! instance-events
         opaque-handle current-store-connection)
(struct state-store (connection lock ephemeral?) #:transparent)
(struct stored-instance (handle principal operation arguments version fingerprint expires revision state) #:transparent)
(define current-store-connection (make-parameter #f))
(define (opaque-handle)
  (apply string-append (for/list ([b (in-bytes (crypto-random-bytes 32))])
                        (define s (number->string b 16)) (if (= (string-length s) 1) (string-append "0" s) s))))
(define (open-store database ephemeral?)
  (define conn (sqlite3-connect #:database database #:mode 'create #:busy-retry-limit 1000))
  (unless ephemeral? (query-exec conn "PRAGMA journal_mode=WAL"))
  (query-exec conn "PRAGMA foreign_keys=ON")
  (query-exec conn "CREATE TABLE IF NOT EXISTS instances (handle TEXT PRIMARY KEY, principal TEXT NOT NULL, operation TEXT NOT NULL, arguments TEXT NOT NULL, version TEXT NOT NULL, fingerprint TEXT NOT NULL, expires INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL, invocation_key TEXT, UNIQUE(principal,operation,invocation_key))")
  (query-exec conn "CREATE TABLE IF NOT EXISTS journal (sequence INTEGER PRIMARY KEY AUTOINCREMENT, handle TEXT NOT NULL REFERENCES instances(handle), event TEXT NOT NULL, recorded INTEGER NOT NULL)")
  (state-store conn (make-semaphore 1) ephemeral?))
(define (open-sqlite-store path) (unless (path-string? path) (raise-argument-error 'open-sqlite-store "explicit path" path)) (open-store path #f))
(define (open-memory-store) (open-store 'memory #t))
(define (close-store! store) (disconnect (state-store-connection store)))
(define (store-transaction store proc)
  (if (eq? (current-store-connection) (state-store-connection store)) (proc)
      (call-with-semaphore (state-store-lock store)
        (lambda () (call-with-transaction (state-store-connection store)
                     (lambda () (parameterize ([current-store-connection (state-store-connection store)]) (proc))) #:option 'immediate)))))
(define (row->instance row)
  (stored-instance (vector-ref row 0) (vector-ref row 1) (vector-ref row 2) (string->json (vector-ref row 3))
                   (vector-ref row 4) (vector-ref row 5) (vector-ref row 6) (vector-ref row 7) (string->json (vector-ref row 8))))
(define (load-instance store handle)
  (store-transaction store
    (lambda () (define row (query-maybe-row (state-store-connection store) "SELECT handle,principal,operation,arguments,version,fingerprint,expires,revision,state FROM instances WHERE handle=?" handle))
      (and row (row->instance row)))))
(define (list-instances store #:operation [operation #f])
  (store-transaction store
    (lambda () (map row->instance
                    (if operation
                        (query-rows (state-store-connection store) "SELECT handle,principal,operation,arguments,version,fingerprint,expires,revision,state FROM instances WHERE operation=?" operation)
                        (query-rows (state-store-connection store) "SELECT handle,principal,operation,arguments,version,fingerprint,expires,revision,state FROM instances"))))))
(define (create-instance! store principal operation arguments version fingerprint expires state #:key [key #f])
  (store-transaction store
    (lambda ()
      (define conn (state-store-connection store))
      (define existing (and key (query-maybe-value conn "SELECT handle FROM instances WHERE principal=? AND operation=? AND invocation_key=?" principal operation key)))
      (cond [existing (define instance (load-instance store existing))
                      (unless (equal? arguments (stored-instance-arguments instance)) (error 'create-instance! "invocation key reused with different arguments")) instance]
            [else (define handle (opaque-handle))
                  (query-exec conn "INSERT INTO instances(handle,principal,operation,arguments,version,fingerprint,expires,state,invocation_key) VALUES (?,?,?,?,?,?,?,?,?)"
                              handle principal operation (json->string arguments) version fingerprint expires (json->string state) (or key sql-null))
                  (record-event! store handle (hasheq 'kind "created")) (load-instance store handle)]))))
(define (update-instance! store instance state)
  (store-transaction store
    (lambda ()
      (query-exec (state-store-connection store) "UPDATE instances SET state=?, revision=revision+1 WHERE handle=? AND revision=?"
                  (json->string state) (stored-instance-handle instance) (stored-instance-revision instance))
      (unless (= 1 (query-value (state-store-connection store) "SELECT changes()")) (error 'update-instance! "concurrent state transition"))
      (load-instance store (stored-instance-handle instance)))))
(define (record-event! store handle event)
  (store-transaction store (lambda () (query-exec (state-store-connection store) "INSERT INTO journal(handle,event,recorded) VALUES (?,?,?)" handle (json->string event) (current-seconds)))))
(define (instance-events store handle)
  (store-transaction store (lambda () (map string->json (query-list (state-store-connection store) "SELECT event FROM journal WHERE handle=? ORDER BY sequence" handle)))))
