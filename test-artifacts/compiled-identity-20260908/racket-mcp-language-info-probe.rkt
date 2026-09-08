#lang racket/base
(require racket/port file/sha1)
(parameterize ([current-namespace (make-base-namespace)])
  (define cell (box #f))
  (define source (syntax-property
    (datum->syntax #f '(module application racket/base (provide value) (define value "old")))
    'module-language (vector 'racket/language-info 'get-info cell)))
  (define code (compile source))
  (printf "same cell: ~a\n" (eq? (vector-ref (module-compiled-language-info code) 2) cell))
  (define id (bytes->hex-string (sha256-bytes (open-input-bytes
    (call-with-output-bytes (lambda (out) (write code out)))))))
  (set-box! cell id)
  (printf "metadata: ~s\n" (module-compiled-language-info code))
  (define stored (call-with-output-bytes (lambda (out) (write code out))))
  (define restored (parameterize ([read-accept-compiled #t]) (read (open-input-bytes stored))))
  (eval restored)
  (printf "loaded metadata: ~s\n" (module->language-info ''application #f)))
