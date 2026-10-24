#lang racket/base
(require "private/storage-schema.rkt"
         "clock.rkt"
         "private/transaction.rkt"
         db
         racket/random
         racket/file
         "json.rkt"
         "private/worker-lock.rkt"
         "private/render-provenance.rkt")
(provide open-sqlite-store open-memory-store close-store! store-transaction
         (struct-out state-store) (struct-out stored-instance)
         create-instance! load-instance list-instances update-instance! record-event! instance-events
         call-with-instance-worker opaque-handle current-store-connection continuation-token! resolve-continuation find-instance-by-key)
(struct state-store (connection lock ephemeral? worker-directory) #:transparent)
(struct supervised-state-store state-store (custodian))
(struct stored-instance (handle principal operation arguments version fingerprint expires revision state) #:transparent)
(define current-store-connection (make-parameter #f))
(define current-store-owner (make-parameter #f))
(define (opaque-handle)
  (apply string-append (for/list ([b (in-bytes (crypto-random-bytes 32))])
                        (define s (number->string b 16)) (if (= (string-length s) 1) (string-append "0" s) s))))
(define (open-store database ephemeral?)
  (define conn (sqlite3-connect #:database database #:mode 'create #:busy-retry-limit 1000))
  (define transferred? #f)
  (dynamic-wind void
    (lambda ()
      (initialize-store-schema! conn ephemeral?)
      (define worker-directory
        (and (not ephemeral?)
             (string->path (string-append (path->string (simplify-path (path->complete-path database))) ".workers"))))
      (when worker-directory
        (make-directory* worker-directory)
        (unless (directory-exists? worker-directory)
          (error 'open-sqlite-store "Worker path is not a directory: ~a" worker-directory)))
      (define result (supervised-state-store conn (make-semaphore 1) ephemeral? worker-directory (make-custodian)))
      (set! transferred? #t)
      result)
    (lambda ()
      (unless transferred?
        ;; Preserve the original exception, break, or arbitrary raised value.
        (with-handlers ([(lambda (_) #t) void]) (disconnect conn))))))
(define (call-with-instance-worker store handle thunk)
  (unless (and (string? handle) (regexp-match? #px"^[0-9a-f]{64}$" handle))
    (raise-argument-error 'call-with-instance-worker "opaque instance handle" handle))
  (define directory (state-store-worker-directory store))
  (define path (and directory (build-path directory handle)))
  (call-with-worker-lock (if path path (cons store handle)) path thunk))
(define (open-sqlite-store path) (unless (path-string? path) (raise-argument-error 'open-sqlite-store "explicit path" path)) (open-store path #f))
(define (open-memory-store) (open-store 'memory #t))
(define (close-store! store)
  (disconnect (state-store-connection store))
  (when (supervised-state-store? store) (custodian-shutdown-all (supervised-state-store-custodian store))))
(define (store-transaction store proc)
  (if (and (eq? (current-store-connection) (state-store-connection store)) (eq? (current-store-owner) (current-thread))) (proc)
      (call-with-owned-transaction
       (state-store-connection store) (state-store-lock store)
       (if (supervised-state-store? store) (supervised-state-store-custodian store) (current-custodian))
       (lambda () (parameterize ([current-store-connection (state-store-connection store)] [current-store-owner (current-thread)]) (proc))))))
(define (decode-stored-json text marks)
  (when (sql-null? marks)
    (error 'load-instance "Stored JSON requires rendering provenance; explicit recovery is required"))
  (restore-render-provenance (string->json text) (string->json marks)))
(define (row->instance row)
  (stored-instance (vector-ref row 0) (vector-ref row 1) (vector-ref row 2) (decode-stored-json (vector-ref row 3) (vector-ref row 10))
                   (vector-ref row 4) (vector-ref row 5) (vector-ref row 6) (vector-ref row 7) (decode-stored-json (vector-ref row 8) (vector-ref row 9))))
(define (load-instance store handle)
  (store-transaction store
    (lambda () (define row (query-maybe-row (state-store-connection store) "SELECT handle,principal,operation,arguments,version,fingerprint,expires,revision,state,state_marks,argument_marks FROM instances WHERE handle=?" handle))
      (and row (row->instance row)))))
(define (find-instance-by-key store principal operation key)
  (store-transaction store
    (lambda ()
      (define handle (query-maybe-value (state-store-connection store)
                                       "SELECT handle FROM instances WHERE principal=? AND operation=? AND invocation_key=?"
                                       principal operation key))
      (and handle (load-instance store handle)))))
(define (continuation-token! store handle stage)
  (store-transaction store
    (lambda ()
      (define conn (state-store-connection store))
      (or (query-maybe-value conn "SELECT token FROM continuations WHERE handle=? AND stage=?" handle (symbol->string stage))
          (let ([token (opaque-handle)])
            (query-exec conn "INSERT INTO continuations(token,handle,stage) VALUES (?,?,?)" token handle (symbol->string stage))
            token)))))
(define (resolve-continuation store token)
  (store-transaction store
    (lambda ()
      (define row (query-maybe-row (state-store-connection store) "SELECT handle,stage FROM continuations WHERE token=?" token))
      (and row (cons (vector-ref row 0) (string->symbol (vector-ref row 1)))))))
(define (list-instances store #:operation [operation #f])
  (store-transaction store
    (lambda () (map row->instance
                    (if operation
                        (query-rows (state-store-connection store) "SELECT handle,principal,operation,arguments,version,fingerprint,expires,revision,state,state_marks,argument_marks FROM instances WHERE operation=?" operation)
                        (query-rows (state-store-connection store) "SELECT handle,principal,operation,arguments,version,fingerprint,expires,revision,state,state_marks,argument_marks FROM instances"))))))
(define (create-instance! store principal operation arguments version fingerprint expires state #:key [key #f])
  (store-transaction store
    (lambda ()
      (define conn (state-store-connection store))
      (define existing (and key (query-maybe-value conn "SELECT handle FROM instances WHERE principal=? AND operation=? AND invocation_key=?" principal operation key)))
      (cond [existing (define instance (load-instance store existing))
                      (unless (equal? arguments (stored-instance-arguments instance)) (error 'create-instance! "invocation key reused with different arguments")) instance]
            [else (define handle (opaque-handle))
                  (query-exec conn "INSERT INTO instances(handle,principal,operation,arguments,version,fingerprint,expires,state,invocation_key,state_marks,argument_marks) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
                              handle principal operation (json->string arguments) version fingerprint expires (json->string state) (or key sql-null) (json->string (render-provenance state)) (json->string (render-provenance arguments)))
                  (record-event! store handle (hasheq 'kind "created")) (load-instance store handle)]))))
(define (update-instance! store instance state)
  (store-transaction store
    (lambda ()
      (query-exec (state-store-connection store) "UPDATE instances SET state=?, state_marks=?, revision=revision+1 WHERE handle=? AND revision=?"
                  (json->string state) (json->string (render-provenance state)) (stored-instance-handle instance) (stored-instance-revision instance))
      (unless (= 1 (query-value (state-store-connection store) "SELECT changes()")) (error 'update-instance! "concurrent state transition"))
      (load-instance store (stored-instance-handle instance)))))
(define (record-event! store handle event)
  (store-transaction store (lambda () (query-exec (state-store-connection store) "INSERT INTO journal(handle,event,recorded,event_marks) VALUES (?,?,?,?)" handle (json->string event) (mcp-current-seconds) (json->string (render-provenance event))))))
(define (instance-events store handle)
  (store-transaction store (lambda () (for/list ([row (in-list (query-rows (state-store-connection store) "SELECT event,event_marks FROM journal WHERE handle=? ORDER BY sequence" handle))]) (decode-stored-json (vector-ref row 0) (vector-ref row 1))))))
