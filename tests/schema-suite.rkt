#lang racket/base
(require racket/file racket/list racket/path racket/runtime-path rackunit mcp/json mcp/schema)
(define-runtime-path fixtures "../vendor/json-schema-tests/tests/draft2020-12")
(define-runtime-path remotes "../vendor/json-schema-tests/remotes")
(define-runtime-path metas "../vendor/metaschemas")
(define registry
  (for/fold ([registry (for/hash ([file (in-directory metas)] #:when (regexp-match? #rx"[.]json$" (path->string file)))
                       (define meta (string->json (file->string file))) (values (hash-ref meta '$id) meta))])
            ([file (in-directory remotes)] #:when (regexp-match? #rx"[.]json$" (path->string file)))
    (hash-set registry (string-append "http://localhost:1234/" (path->string (find-relative-path (simplify-path remotes) (simplify-path file))))
              (string->json (file->string file) #:max-bytes 10000000))))
;; This runner reports unsupported features as failures, never silently skips them.
(module+ main
  (define passed 0) (define failed 0)
  (for ([file (in-list (sort (directory-list fixtures #:build? #t) path<?))] #:when (regexp-match? #rx"[.]json$" (path->string file)))
    (define groups (string->json (file->string file) #:max-bytes 10000000))
    (for ([group (in-list groups)])
      (for ([test (in-list (hash-ref group 'tests))])
        (define got (with-handlers ([exn:fail? (lambda (e) 'unsupported)]) (valid? (hash-ref group 'schema) (hash-ref test 'data) #:registry registry)))
        (if (equal? got (hash-ref test 'valid)) (set! passed (add1 passed))
            (begin (set! failed (add1 failed))
                   (printf "FAIL ~a: ~a / ~a (~a)\n" (file-name-from-path file) (hash-ref group 'description) (hash-ref test 'description) got))))))
  (printf "~a passed; ~a failed or unsupported\n" passed failed)
  (unless (zero? failed) (exit 1)))
