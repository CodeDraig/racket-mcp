#lang racket/base
(require "descriptor.rkt" "json.rkt" "storage.rkt" "upstream-bridge.rkt" "private/upstream-task-recovery.rkt"
         "private/upstream-snapshot.rkt" "private/upstream-invocation.rkt" "private/upstream-resources.rkt"
         "private/upstream-prompts.rkt" "private/upstream-completions.rkt" "private/upstream-tools.rkt")
(provide capture-snapshot make-upstream-interface upstream-resource-change-keys check-upstream-compatibility! recover-upstream-task! retry-upstream-task! (struct-out upstream-template-adapter))
(provide (all-from-out "upstream-bridge.rkt"))

(define (retry-upstream-task! bridge store snapshot request id #:principal principal #:credential-id credential
                              #:authorize [authorize void])
  (unless (and (procedure? request) (procedure-arity-includes? request 2))
    (raise-argument-error 'retry-upstream-task! "request procedure accepting method and parameters" request))
  (retry-upstream-task/core! bridge store snapshot request id principal credential authorize
    (lambda () (check-upstream-compatibility! snapshot request))))
(define (make-upstream-interface supplied-snapshot request #:templates [templates (hash)] #:bridge [bridge #f])
  (unless (or (not bridge) (upstream-bridge? bridge)) (raise-argument-error 'make-upstream-interface "upstream-bridge? or #f" bridge))
  (define snapshot (string->json (json->string supplied-snapshot)))
  ;; Each installation retains its own verification and freshness domains.
  (define freshness-source (opaque-handle))
  (define-values (invoke verify-for) (make-upstream-invocation snapshot request bridge))
  (define-values (resources remap-content)
    (make-upstream-resources snapshot templates invoke bridge freshness-source))
  (define prompts (make-upstream-prompts snapshot invoke bridge remap-content))
  (define completions (make-upstream-completions snapshot resources prompts invoke))
  (make-interface #:resources resources #:prompts prompts #:completions completions
    #:tools (make-upstream-tools snapshot request invoke bridge verify-for remap-content)))
