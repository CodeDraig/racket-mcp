#lang racket/base
(require racket/file racket/runtime-path racket/promise "../json.rkt")
(provide standard-metaschemas)
;; These offline inputs are pinned and hashed by vendor/LOCK.json. Packaging
;; includes vendor/metaschemas; loading schemas never fetches network resources.
(define-runtime-path directory "../../vendor/metaschemas")
(define schemas
  (delay
    (for/hash ([path (in-directory directory)] #:when (regexp-match? #rx"[.]json$" (path->string path)))
      (define schema (string->json (file->string path)))
      (values (hash-ref schema '$id) schema))))
(define (standard-metaschemas) (force schemas))
