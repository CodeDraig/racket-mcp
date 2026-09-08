#lang racket/base
(require racket/file racket/list racket/port racket/runtime-path rackunit mcp mcp/rendering)
(define-runtime-path self "mcp-render-boundaries.rkt")
(module+ main
  (define argv (current-command-line-arguments))
  (define directory (vector-ref argv 0))
  (define boundary (vector-ref argv 1))
  (define starting? (equal? (vector-ref argv 2) "start"))
  (define store (open-sqlite-store (build-path directory "state.sqlite")))
  (define (pause name)
    (when (and starting? (equal? boundary name))
      (displayln "ready") (flush-output) (sync never-evt)))
  (define form (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
  (define (resolve uri token responses key)
    (when (equal? uri "test:///two") (pause "parent-after"))
    (define flow
      (make-workflow uri "1" "fixed-child-code"
        (list
          (workflow-stage 'saved 'checkpoint String
            (lambda (_)
              (call-with-output-file (build-path directory "reads") #:exists 'append
                (lambda (out) (displayln uri out))) uri) #f #f)
          (workflow-stage 'answer 'input Any (lambda (_) form) #f #f)
          (workflow-stage 'done 'complete Any
            (lambda (env) (hasheq 'resultType "complete" 'contents
              (list (hasheq 'uri uri 'text (hash-ref env 'saved))))) #f #f))
        #:key (lambda (_) key)))
    (define result (run-workflow flow store (hasheq) #:principal "alice" #:state token #:responses responses))
    (when (equal? uri "test:///one")
      (pause (if (equal? (hash-ref result 'resultType) "input_required") "child-pending-before-parent" "child-complete-before-parent")))
    result)
  (define layout
    (parameterize ([current-render-capture (box 0)])
      (list (deferred-embedding "test:///one") (deferred-embedding "test:///two"))))
  (define (call token responses)
    (render-layout store layout #:operation "parent" #:arguments (hasheq) #:principal "alice"
      #:fingerprint "fixed-parent-code" #:resolve resolve #:state token #:responses responses #:key "one"))
  (define result
    (let loop ([result (call #f (hasheq))])
      (if (list? result) result
          (loop (call (hash-ref result 'requestState)
                  (for/hasheq ([id (in-hash-keys (hash-ref result 'inputRequests))])
                    (values id (hasheq 'action "decline"))))))))
  (write-json result) (newline) (close-store! store))
(module+ test
  (define root (make-temporary-file "mcp-render-boundaries-~a" 'directory))
  (define (spawn directory boundary mode)
    (define-values (p out in err)
      (subprocess #f #f #f (find-executable-path "racket") self directory boundary mode))
    (close-output-port in) (values p out err))
  (define (cleanup p out err)
    (when (eq? (subprocess-status p) 'running) (subprocess-kill p #t))
    (subprocess-wait p) (close-input-port out) (close-input-port err))
  (define (resume directory boundary)
    (define-values (p out err) (spawn directory boundary "resume"))
    (dynamic-wind void
      (lambda ()
        (unless (sync/timeout 15 p) (error 'test "resume timed out"))
        (define output (port->string out))
        (check-equal? (subprocess-status p) 0 (port->string err))
        (string->json output))
      (lambda () (cleanup p out err))))
  (dynamic-wind void
    (lambda ()
      (for ([boundary '("child-pending-before-parent" "child-complete-before-parent" "parent-after")])
        (test-case boundary
          (define directory (build-path root boundary)) (make-directory directory)
          (define-values (p out err) (spawn directory boundary "start"))
          (dynamic-wind void
            (lambda ()
              (unless (sync/timeout 15 out) (error 'test "boundary timed out"))
              (check-equal? (read-line out) "ready")
              (check-equal? (subprocess-status p) 'running))
            (lambda () (cleanup p out err)))
          (define store (open-sqlite-store (build-path directory "state.sqlite")))
          (dynamic-wind void
            (lambda ()
              (define parent (car (list-instances store #:operation "render:parent")))
              (define child (car (list-instances store #:operation "test:///one")))
              (check-equal? (hash-ref (stored-instance-state child) 'status)
                (if (equal? boundary "child-pending-before-parent") "input_required" "completed"))
              (check-equal? (hash-ref (car (hash-ref (stored-instance-state parent) 'children)) 'status)
                (cond [(equal? boundary "child-pending-before-parent") "pending"]
                      [(equal? boundary "child-complete-before-parent") "input_required"] [else "complete"]))
              (check-equal? (list-instances store #:operation "test:///two") '()))
            (lambda () (close-store! store)))
          (define result (resume directory boundary))
          (check-equal? (map (lambda (item) (hash-ref (hash-ref item 'resource) 'text)) result)
                        '("test:///one" "test:///two"))
          (check-equal? (resume directory boundary) result)
          (check-equal? (file->lines (build-path directory "reads")) '("test:///one" "test:///two")))))
    (lambda () (delete-directory/files root))))
