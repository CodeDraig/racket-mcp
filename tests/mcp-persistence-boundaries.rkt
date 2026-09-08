#lang racket/base
(require racket/file racket/list racket/port racket/runtime-path rackunit mcp)
(define-runtime-path self "mcp-persistence-boundaries.rkt")
(module+ main
  (define argv (current-command-line-arguments))
  (define directory (vector-ref argv 0))
  (define boundary (vector-ref argv 1))
  (define starting? (equal? (vector-ref argv 2) "start"))
  (define store (open-sqlite-store (build-path directory "state.sqlite")))
  (define (mark name)
    (call-with-output-file (build-path directory name) #:exists 'append
      (lambda (out) (displayln "called" out))))
  (define (pause name)
    (when (and starting? (equal? boundary name))
      (displayln "ready") (flush-output) (sync never-evt)))
  (define form (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
  (define flow
    (make-workflow "boundaries" "1" "fixed-test-program"
      (list
        (workflow-stage 'choice 'branch Integer
          (lambda (_) (mark "branch") (pause "branch-before") 0) '(saved) #f)
        (workflow-stage 'saved 'checkpoint Integer
          (lambda (_) (pause "branch-after") (mark "checkpoint") (pause "checkpoint-before") 42) #f #f)
        (workflow-stage 'answers 'input-group (object-schema (hasheq 'a Any 'b Any))
          (lambda (_) (mark "input") (pause "input-before") (hasheq 'a form 'b form)) '(a b) #f)
        (workflow-stage 'done 'complete Any
          (lambda (env) (pause "complete-before") (structured-result env)) #f #f))
      #:key (lambda (_) "one")))
  (define args (hasheq 'original "kept"))
  (define (call [state #f] [responses (hasheq)])
    (run-workflow flow store args #:principal "alice" #:state state #:responses responses))
  (define initial (call))
  (pause "input-after")
  (define result
    (if (equal? (hash-ref initial 'resultType) "complete") initial
        (let* ([token (hash-ref initial 'requestState)]
               [partial (call token (hasheq 'a (hasheq 'action "decline")))])
          (pause "partial-after")
          (call token (hasheq 'b (hasheq 'action "cancel"))))))
  (pause "terminal-after")
  (write-json result) (newline)
  (close-store! store))
(module+ test
  (define root (make-temporary-file "mcp-persistence-boundaries-~a" 'directory))
  (define (spawn directory boundary mode)
    (define-values (p out in err)
      (subprocess #f #f #f (find-executable-path "racket") self directory boundary mode))
    (close-output-port in)
    (values p out err))
  (define (resume directory boundary)
    (define-values (p out err) (spawn directory boundary "resume"))
    (dynamic-wind void
      (lambda ()
        (unless (sync/timeout 15 p) (error 'test "resume timed out"))
        (define output (port->string out))
        (check-equal? (subprocess-status p) 0 (port->string err))
        (string->json output))
      (lambda ()
        (when (eq? (subprocess-status p) 'running) (subprocess-kill p #t) (subprocess-wait p))
        (close-input-port out) (close-input-port err))))
  (dynamic-wind void
    (lambda ()
      (for ([boundary '("branch-before" "branch-after" "checkpoint-before" "input-before"
                        "input-after" "partial-after" "complete-before" "terminal-after")])
        (test-case boundary
          (define directory (build-path root boundary)) (make-directory directory)
          (define-values (p out err) (spawn directory boundary "start"))
          (dynamic-wind void
            (lambda ()
              (unless (sync/timeout 15 out) (error 'test "boundary timed out"))
              (check-equal? (read-line out) "ready")
              (check-equal? (subprocess-status p) 'running))
            (lambda ()
              (when (eq? (subprocess-status p) 'running) (subprocess-kill p #t))
              (subprocess-wait p) (close-input-port out) (close-input-port err)))
          (define store (open-sqlite-store (build-path directory "state.sqlite")))
          (dynamic-wind void
            (lambda ()
              (define row (car (list-instances store #:operation "boundaries")))
              (define state (stored-instance-state row))
              (define position (cond [(equal? boundary "branch-before") 0]
                                     [(member boundary '("branch-after" "checkpoint-before")) 1]
                                     [(member boundary '("complete-before" "terminal-after")) 3]
                                     [else 2]))
              (check-equal? (hash-ref state 'position) position)
              (check-equal? (hash-has-key? (hash-ref state 'values) 'saved) (>= position 2))
              (check-equal? (hash-ref state 'status) (cond [(equal? boundary "terminal-after") "completed"]
                  [(member boundary '("input-after" "partial-after")) "input_required"] [else "working"]))
              (when (equal? boundary "partial-after")
                (check-equal? (hash-ref (hash-ref state 'values) 'a) (hasheq 'action "decline"))
                (check-false (hash-has-key? (hash-ref state 'values) 'b))))
            (lambda () (close-store! store)))
          (define result (resume directory boundary))
          (check-equal? (hash-ref result 'structuredContent)
            (hasheq 'original "kept" 'choice 0 'saved 42 'a (hasheq 'action "decline")
              'b (hasheq 'action "cancel") 'answers (hasheq 'a (hasheq 'action "decline") 'b (hasheq 'action "cancel"))))
          (check-equal? (resume directory boundary) result)
          (for ([name '("branch" "checkpoint" "input")]
                [expected (list (if (equal? boundary "branch-before") 2 1)
                                (if (equal? boundary "checkpoint-before") 2 1)
                                (if (equal? boundary "input-before") 2 1))])
            (check-equal? (length (file->lines (build-path directory name))) expected name)))))
    (lambda () (delete-directory/files root))))
