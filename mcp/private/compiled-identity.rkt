#lang racket/base
;; Producer metadata lives in the module declaration itself. A lazy submodule
;; could be loaded from a replacement file after the parent was declared.
(provide compile-with-module-identity compiled-module-producer-identity
         declared-module-producer-identity get-info)
(define provider 'mcp/private/compiled-identity)
(define format-tag 'mcp-compiled/1)
(define (module-source? expression)
  (define value (if (syntax? expression) (syntax-e expression) expression))
  (and (pair? value)
       (eq? (if (syntax? (car value)) (syntax-e (car value)) (car value)) 'module)))
(define (identity-data info)
  (and (vector? info) (= (vector-length info) 3)
       (equal? (vector-ref info 0) provider) (eq? (vector-ref info 1) 'get-info)
       (let ([data (vector-ref info 2)])
         (unless (and (vector? data) (= (vector-length data) 3)
                      (eq? (vector-ref data 0) format-tag) (box? (vector-ref data 2)))
           (error 'compiled-identity "malformed producer metadata"))
         data)))
(define (data-identity data)
  (define id (unbox (vector-ref data 2)))
  (unless (and (string? id) (regexp-match? #px"^mcp-compiled/1:[0-9a-f]{64}$" id))
    (error 'compiled-identity "producer identity is incomplete or malformed"))
  (string->immutable-string id))
(define (compiled-module-producer-identity code)
  (define data (identity-data (module-compiled-language-info code)))
  (and data (data-identity data)))
(define (declared-module-producer-identity identity)
  (unless (resolved-module-path? identity)
    (raise-argument-error 'declared-module-producer-identity "resolved-module-path?" identity))
  ;; Passing a resolved path and #f cannot load a replacement from the filesystem.
  (define data (identity-data (module->language-info identity #f)))
  (and data (data-identity data)))
(define (get-info data)
  (define checked (identity-data (vector provider 'get-info data)))
  (define id (data-identity checked))
  (define original (vector-ref checked 1))
  (define delegate #f)
  (lambda (key default)
    (cond [(eq? key 'mcp-executable-identity) id]
          [original
           (unless delegate
             (set! delegate ((dynamic-require (vector-ref original 0) (vector-ref original 1))
                             (vector-ref original 2))))
           (delegate key default)]
          [else default])))
(define (compile-with-module-identity expression immediate? compiler)
  (cond
    [(not (module-source? expression)) (compiler expression immediate?)]
    [else
     (define source (if (syntax? expression) expression
                        (namespace-syntax-introduce (datum->syntax #f expression))))
     (define prior (syntax-property source 'module-language))
     (define pending (identity-data prior))
     (cond
       ;; Another enclosing compilation hook owns this unfilled cell. It fills
       ;; it before returning the artifact. Readers reject any unfilled identity.
       [(and pending (not (unbox (vector-ref pending 2)))) (compiler source immediate?)]
       [else
        (when pending (data-identity pending))
        (define original (if pending (vector-ref pending 1) prior))
        (unless (or (not original)
                    (and (vector? original) (= (vector-length original) 3)
                         (module-path? (vector-ref original 0)) (symbol? (vector-ref original 1))))
          (error 'compiled-identity "malformed original language information"))
        (define cell (box #f))
        (define data (vector-immutable format-tag original cell))
        (define info (vector-immutable provider 'get-info data))
        ;; Immediate-only linklets cannot be serialized. Request saveable code
        ;; once for modules; non-module compilation retains the caller's hint.
        (define code (compiler (syntax-property source 'module-language info) #f))
        (unless (and (compiled-module-expression? code)
                     (eq? (identity-data (module-compiled-language-info code)) data))
          (error 'compiled-identity "compiler discarded producer metadata"))
        ;; Compile once. Hash with the unfilled cell, then fill the metadata that
        ;; the compiled declaration retains. No transformer or handler is replayed.
        (define out (open-output-bytes))
        (write code out)
        (define digest (sha256-bytes (open-input-bytes (get-output-bytes out))))
        (define hex
          (build-string (* 2 (bytes-length digest))
            (lambda (i)
              (define b (bytes-ref digest (quotient i 2)))
              (string-ref "0123456789abcdef" (if (even? i) (quotient b 16) (remainder b 16))))))
        (set-box! cell (string->immutable-string (string-append "mcp-compiled/1:" hex)))
        code])]))
