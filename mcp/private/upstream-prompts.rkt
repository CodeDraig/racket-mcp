#lang racket/base
(require "../descriptor.rkt" "../schema.rkt" "../json.rkt" "upstream-invocation.rkt")
(provide make-upstream-prompts)
(define (make-upstream-prompts snapshot invoke bridge remap-content)
  (define prompts
    (for/list ([wire (in-list (hash-ref (hash-ref snapshot 'prompts/list) 'prompts))])
      (define name (hash-ref wire 'name))
      (define arguments
        (for/list ([arg (in-list (hash-ref wire 'arguments '()))])
          (argument (string->symbol (hash-ref arg 'name)) String (not (hash-ref arg 'required #f)) #f)))
      (make-prompt name arguments
        (durable-handler bridge (lambda (bound)
          (define result (invoke "prompts/get" (hasheq 'name name 'arguments
            (for/hasheq ([(key value) (in-hash bound)] #:unless (missing? value)) (values key value)))))
          (if (pending? result) result
          (hash-set result 'messages
            (for/list ([message (in-list (hash-ref result 'messages))])
              (hash-set message 'content (remap-content (hash-ref message 'content))))))))
        #:description (hash-ref wire 'description ""))))
  prompts)
