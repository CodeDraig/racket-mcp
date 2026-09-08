#lang racket/base
(require rackunit racket/file racket/path racket/port compiler/cm
         mcp/private/compiled-identity mcp/private/executable-capture)
(define compiler (current-compile))
(define directory (make-temporary-file "mcp-retained-capture-~a" 'directory))
(define helper (build-path directory "helper.rkt"))
(define artifact (build-path directory "compiled" "helper_rkt.zo"))
(define root (build-path directory "root.rkt"))
(define (write-helper value stamped?)
  (define code
    (parameterize ([current-namespace (make-base-namespace)])
      (define source (namespace-syntax-introduce (datum->syntax #f
        `(module helper racket/base (provide helper set-value!)
           (define state (box ,value)) (define (helper) (unbox state))
           (define (set-value! v) (set-box! state v))))))
      (if stamped? (compile-with-module-identity source #f compiler) (compiler source #f))))
  (display-to-file "#lang racket/base\n" helper #:exists 'truncate)
  (make-directory* (path-only artifact))
  (call-with-output-file artifact (lambda (out) (write code out)) #:exists 'truncate)
  (module-cache-clear!)
  (compiled-module-producer-identity code))
(define (preload)
  (define namespace (make-base-namespace))
  (parameterize ([current-namespace namespace] [current-compiled-file-roots '(same)])
    (dynamic-require helper #f))
  namespace)
(define helper-name (format "~s" helper))
(define (digest capture) (hash-ref (module-code-capture-observed capture) helper-name #f))
(dynamic-wind void
  (lambda ()
    (for ([stamped? '(#f #t)])
      (test-case (format "retained helper identity stamped=~a" stamped?)
        (define old-id (write-helper "old" stamped?))
        (define namespace (preload))
        (define new-id (write-helper "new" #t))
        (display-to-file "#lang racket/base\n(require \"helper.rkt\")\n(provide read-value)\n(define (read-value) (helper))\n"
          root #:exists 'truncate)
        (define capture (capture-module-export root 'read-value #:namespace namespace))
        (check-equal? ((module-code-capture-value capture)) "old")
        (check-equal? (digest capture) old-id)
        (check-not-equal? (digest capture) new-id)
        (if stamped?
            (check-false (member helper-name (module-code-capture-unobserved capture)))
            (begin
              (check-not-false (member helper-name (module-code-capture-unobserved capture)))
              (check-exn #rx"unobserved executable dependencies"
                (lambda () (seal-module-code-capture! capture)))))))
    (test-case "sealed workflows retain preloaded helper identity across code replacement"
      (define database (build-path directory "state.sqlite"))
      (define completed (path->string (build-path directory "state.sqlite.done")))
      (define old-id (write-helper "old" #t))
      (define old-namespace (preload))
      (display-to-file #<<APPLICATION
#lang racket/base
(require mcp "helper.rkt")
(provide execute)
(workflow (work) #:version "1"
  (checkpoint [saved String] (helper))
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Continue?"
      'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (text-result
    (begin
      (call-with-output-file (string-append (current-database) ".done") #:exists 'append
        (lambda (out) (displayln (helper) out)))
      (helper))))
(define current-database (make-parameter #f))
(define (execute database state)
  (define store (open-sqlite-store database))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-database database])
        (with-handlers ([exn:fail:recovery? (lambda (e) (hasheq 'rejected #t 'message (exn-message e)))])
          (run-workflow (tool-descriptor-workflow work) store (hasheq) #:principal "alice"
            #:state state #:responses
            (if state (hasheq 'answer (hasheq 'action "accept" 'content (hasheq 'ok #t))) (hasheq))))))
    (lambda () (close-store! store))))
APPLICATION
        root #:exists 'truncate)
      (define (capture namespace expected)
        (module-cache-clear!)
        (define result (capture-module-export root 'execute #:namespace namespace))
        (check-equal? (digest result) expected)
        (check-false (member helper-name (module-code-capture-unobserved result)))
        ;; Only the remaining SDK/runtime baseline is explicitly supplied. The
        ;; helper must have its own retained evidence, checked above.
        (void (seal-module-code-capture! result #:dependencies
          (for/hash ([name (module-code-capture-unobserved result)]) (values name "fixture-runtime"))))
        (module-code-capture-value result))
      (define old (capture old-namespace old-id))
      (define pending (old (path->string database) #f))
      (check-equal? (hash-ref pending 'resultType) "input_required")
      (define new-id (write-helper "new" #t))
      (define newer (capture (preload) new-id))
      (check-true (hash-ref (newer (path->string database) (hash-ref pending 'requestState)) 'rejected #f))
      (check-false (file-exists? completed))
      (define resumed (old (path->string database) (hash-ref pending 'requestState)))
      (check-equal? (hash-ref (car (hash-ref resumed 'content)) 'text) "old")
      (check-equal? (file->string completed) "old\n")
      (define fresh (newer (path->string database) #f))
      (define finished (newer (path->string database) (hash-ref fresh 'requestState)))
      (check-equal? (hash-ref (car (hash-ref finished 'content)) 'text) "new")
      (check-equal? (file->string completed) "old\nnew\n")))
  (lambda () (delete-directory/files directory)))
