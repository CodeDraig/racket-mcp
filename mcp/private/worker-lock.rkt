#lang racket/base
(require racket/file)
(provide call-with-worker-lock)
;; File locks arbitrate processes. The thread registry also arbitrates platforms
;; where independent ports in the same process can acquire the same file lock.
(struct owner (thread port) #:mutable)
(define owners (make-hash))
(define guard (make-semaphore 1))
(define (call-with-worker-lock key lock-file thunk)
  (define mine (owner (current-thread) #f))
  (define acquired?
    (call-with-semaphore guard
      (lambda ()
        (define previous (hash-ref owners key #f))
        (when (and previous (thread-dead? (owner-thread previous)))
          (when (owner-port previous) (close-output-port (owner-port previous)))
          (hash-remove! owners key))
        (and (not (hash-has-key? owners key))
             (begin (hash-set! owners key mine) #t)))))
  (and acquired?
       (dynamic-wind
         void
         (lambda ()
           (define port (and lock-file (open-output-file lock-file #:exists 'append)))
           (set-owner-port! mine port)
           (and (or (not port) (port-try-file-lock? port 'exclusive))
                (begin (thunk) #t)))
         (lambda ()
           (when (owner-port mine) (close-output-port (owner-port mine)))
           (call-with-semaphore guard
             (lambda () (when (eq? mine (hash-ref owners key #f)) (hash-remove! owners key))))))))
