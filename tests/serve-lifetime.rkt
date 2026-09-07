#lang racket/base
(require rackunit racket/file mcp mcp/cli)
(define directory (make-temporary-file "mcp-serving-lifetime-~a" 'directory))
(define root (current-custodian))
(tool (duplicate) (text-result "unused"))
(define bad (interface-descriptor (server-descriptor "bad" "1" #f) (list duplicate duplicate) '() '() '()))
(define good (interface-descriptor (server-descriptor "good" "1" #f) (list duplicate) '() '() '()))
(define (check-lifetime thunk)
  (define owner (make-custodian))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-custodian owner])
        ;; This worker belongs to the caller, not the serving lifetime.
        (define caller-worker (thread (lambda () (sync never-evt))))
        (define before (custodian-managed-list owner root))
        (thunk)
        (check-false (thread-dead? caller-worker))
        ;; No GC: closed connections and child custodians must unregister now.
        (check-equal? (custodian-managed-list owner root) before)))
    (lambda () (custodian-shutdown-all owner))))
(dynamic-wind void
  (lambda ()
    (check-lifetime
     (lambda ()
       (check-exn #rx"duplicate published identity"
                  (lambda () (serve-interface bad #:state (build-path directory "invalid.sqlite"))))))
    (check-lifetime
     (lambda ()
       (check-exn #rx"unknown transport"
                  (lambda () (serve-interface good #:transport "invalid" #:state (build-path directory "transport.sqlite"))))))
    (check-lifetime
     (lambda ()
       (parameterize ([current-input-port (open-input-string "")]
                      [current-output-port (open-output-string)])
         (serve-interface good #:state (build-path directory "eof.sqlite")))))
    (check-lifetime
     (lambda ()
       (parameterize ([current-input-port (open-input-string "")]
                      [current-output-port (open-output-string)])
         (serve-interface good))))
    (define path (build-path directory "denied.sqlite"))
    (define worker-path (string->path (string-append (path->string path) ".workers")))
    (define sentinel (gensym 'startup-failure))
    (define guard
      (make-security-guard (current-security-guard)
        (lambda (_ path modes)
          (when (and path (equal? path worker-path) (memq 'write modes)) (raise sentinel)))
        (lambda args (void))))
    (check-lifetime
     (lambda ()
       (parameterize ([current-security-guard guard])
         (check-exn (lambda (raised) (eq? raised sentinel))
                    (lambda () (serve-interface good #:state path))))))
    (check-lifetime
     (lambda ()
       (define break-guard
         (make-security-guard (current-security-guard)
           (lambda (_ candidate modes)
             (when (and candidate (equal? candidate worker-path) (memq 'write modes))
               (break-thread (current-thread))))
           (lambda args (void))))
       (parameterize ([current-security-guard break-guard])
         (check-exn exn:break? (lambda () (serve-interface good #:state path))))))
    (check-lifetime
     (lambda ()
       (check-eq?
        (let/ec escape
          (define escape-guard
            (make-security-guard (current-security-guard)
              (lambda (_ candidate modes)
                (when (and candidate (equal? candidate worker-path) (memq 'write modes))
                  (escape sentinel)))
              (lambda args (void))))
          (parameterize ([current-security-guard escape-guard])
            (serve-interface good #:state path)))
        sentinel))))
  (lambda () (delete-directory/files directory)))
