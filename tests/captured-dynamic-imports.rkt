#lang racket/base
(require rackunit racket/file racket/path racket/string
         mcp/private/executable-capture)
(define directory (make-temporary-file "mcp-dynamic-build-~a" 'directory))
(define deep (build-path directory "deep.rkt"))
(define late (build-path directory "late.rkt"))
(define root (build-path directory "application.rkt"))
(define loaded (build-path directory "loaded.txt"))
(define called (build-path directory "called.txt"))
(define (name path) (format "~s" path))
(define (write-file path text)
  (call-with-output-file path #:exists 'truncate (lambda (out) (display text out))))
(define (write-root preload?)
  (call-with-output-file root #:exists 'truncate
    (lambda (out)
      (displayln "#lang racket/base\n(require mcp)\n(provide run)" out)
      (when preload? (fprintf out "(dynamic-require '~s #f)\n" `(file ,(path->string late))))
      (write `(workflow (work) #:version "1"
                (text-result ((dynamic-require '(file ,(path->string late)) 'touch)))) out)
      (newline out)
      (displayln
        "(define (run)
           (define store (open-memory-store))
           (dynamic-wind void
             (lambda () (run-workflow (tool-descriptor-workflow work) store (hasheq) #:principal \"alice\"))
             (lambda () (close-store! store))))" out))))
(define (seal capture [known (hash)])
  (seal-module-code-capture! capture
    #:dependencies
    (for/hash ([identity (in-list (module-code-capture-unobserved capture))])
      (values identity
        (hash-ref known identity
          (lambda ()
            (when (string-contains? identity (path->string directory))
              (error 'test "uncaptured application dependency: ~a" identity))
            "explicit-test-bootstrap/1"))))))
(dynamic-wind void
  (lambda ()
    (write-file deep "#lang racket/base\n(provide deep)\n(define deep (box \"late\"))\n")
    (call-with-output-file late
      (lambda (out)
        (displayln "#lang racket/base\n(require \"deep.rkt\")\n(provide touch)" out)
        (fprintf out "(call-with-output-file ~s #:exists 'append (lambda (out) (displayln \"loaded\" out)))\n"
                 (path->string loaded))
        (fprintf out "(define (touch) (call-with-output-file ~s #:exists 'append (lambda (out) (displayln \"called\" out))) (unbox deep))\n"
                 (path->string called))))
    (write-root #f)
    (define absent (capture-module-export root 'run))
    (void (seal absent))
    (define before-namespace (current-namespace))
    (define before-resolver (current-module-name-resolver))
    (check-exn #rx"not loaded in the sealed executable" (module-code-capture-value absent))
    (check-false (file-exists? loaded))
    (check-false (file-exists? called))
    (check-eq? (current-namespace) before-namespace)
    (check-eq? (current-module-name-resolver) before-resolver)
    ;; A declaration already in the namespace is not automatically in the build.
    (define unrelated-namespace (make-base-namespace))
    (parameterize ([current-namespace unrelated-namespace]) (dynamic-require late #f))
    (check-true (file-exists? loaded))
    (define unrelated (capture-module-export root 'run #:namespace unrelated-namespace))
    (void (seal unrelated))
    (check-exn #rx"not loaded in the sealed executable" (module-code-capture-value unrelated))
    (check-false (file-exists? called))
    ;; Capture deep first, retaining its real observed identity for reuse. The
    ;; next capture must report it as an unobserved dependency of dynamically
    ;; loaded late, even though late is not a static import of application.
    (define namespace (make-base-namespace))
    (define deep-capture (capture-module-export deep 'deep #:namespace namespace))
    (define deep-identity (hash-ref (module-code-capture-observed deep-capture) (name deep)))
    (write-root #t)
    (define prepared (capture-module-export root 'run #:namespace namespace))
    (check-true (hash-has-key? (module-code-capture-observed prepared) (name late)))
    (check-not-false (member (name deep) (module-code-capture-unobserved prepared)))
    (check-exn #rx"explicit identities" (lambda () (seal-module-code-capture! prepared)))
    (void (seal prepared (hash (name deep) deep-identity)))
    (define outcome ((module-code-capture-value prepared)))
    (check-equal? (hash-ref outcome 'resultType) "complete")
    (check-equal? (hash-ref (car (hash-ref outcome 'content)) 'text) "late")
    (check-equal? (file->string called) "called\n")
    ;; Replacing the file and loading it in the caller's namespace does not
    ;; replace the executable already captured for this workflow.
    (write-file late "#lang racket/base\n(provide touch)\n(define (touch) \"changed-file\")\n")
    (parameterize ([current-namespace (make-base-namespace)])
      (check-equal? ((dynamic-require late 'touch)) "changed-file")
      (define retained ((module-code-capture-value prepared)))
      (check-equal? (hash-ref (car (hash-ref retained 'content)) 'text) "late"))
    (check-equal? (file->string called) "called\ncalled\n")
    (check-eq? (current-namespace) before-namespace)
    (check-eq? (current-module-name-resolver) before-resolver))
  (lambda () (delete-directory/files directory)))
