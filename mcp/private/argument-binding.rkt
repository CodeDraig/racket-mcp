#lang racket/base
(require "descriptor-types.rkt" "../schema.rkt" "../json.rkt" "../codec.rkt" "../error.rkt")
(provide bind-arguments encode-prompt-arguments prompt-codec-fingerprint)
(define (prompt-codec-fingerprint descriptor)
  (json->string
   (for/list ([a (in-list (prompt-descriptor-arguments descriptor))] #:when (prompt-argument? a))
     (define codec (prompt-argument-codec a))
     (hasheq 'argument (symbol->string (argument-name a)) 'name (string-codec-name codec)
             'version (string-codec-version codec) 'schema (string-codec-schema codec)))))
(define (encode-prompt-arguments descriptor arguments)
  (unless (hash? arguments) (raise-argument-error 'encode-prompt-arguments "hash?" arguments))
  (for/hasheq ([(name value) (in-hash arguments)] #:unless (missing? value))
    (define a (findf (lambda (a) (eq? name (argument-name a))) (prompt-descriptor-arguments descriptor)))
    (unless a (error 'encode-prompt-arguments "unknown argument ~a" name))
    (unless (valid? (argument-schema a) value) (error 'encode-prompt-arguments "invalid argument ~a" name))
    (define wire (if (prompt-argument? a) (encode-string-value (prompt-argument-codec a) value) value))
    (unless (string? wire) (error 'encode-prompt-arguments "non-string argument requires a codec"))
    (values name wire)))
(define (bind-arguments arguments input)
  (unless (hash? input) (error 'bind-arguments "arguments must be an object"))
  (for/fold ([bound (hasheq)]) ([a (in-list arguments)])
    (define supplied (hash-ref input (argument-name a) missing))
    (define v (cond [(not (missing? supplied)) (if (prompt-argument? a) (with-handlers ([exn:fail? (lambda (e) (mcp-error -32602 (format "Invalid string argument ~a" (argument-name a))))])
                      (decode-string-value (prompt-argument-codec a) supplied)) supplied)]
                    [(argument-default a) ((argument-default a) bound)]
                    [(argument-optional? a) missing]
                    [else (error 'bind-arguments "missing argument ~a" (argument-name a))]))
    (unless (or (missing? v) (valid? (argument-schema a) v)) (error 'bind-arguments "invalid argument ~a" (argument-name a)))
    (hash-set bound (argument-name a) v)))
