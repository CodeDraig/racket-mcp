#lang racket/base
(require file/sha1 racket/promise)
(provide running-executable-identity)
;; This identifies only the executable image, not its shared libraries or the
;; complete runtime distribution. Linux procfs follows the running image even
;; after its original pathname has been replaced. Never substitute that pathname.
;; Unavailable evidence leaves the existing explicit runtime contract in force.
(define executable-identity
  (delay/sync
    (and (eq? (system-type 'os*) 'linux)
         (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
           (call-with-input-file "/proc/self/exe"
             (lambda (in)
               (string->immutable-string
                 (string-append "linux-proc-exe/1:"
                                (bytes->hex-string (sha256-bytes in))))))))))
(define (running-executable-identity) (force executable-identity))
