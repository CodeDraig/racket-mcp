#lang racket/base
(require racket/list "../build.rkt" (submod "../build.rkt" private) "workflow-types.rkt"
         "workflow-contract.rkt" "workflow-context.rkt" "executable-build.rkt" "../json.rkt" "../codec.rkt" "../effect.rkt")
(provide make-workflow workflow-executable-fingerprint workflow-add-fingerprint-suffix workflow-invocation-key call-with-workflow-build)
(struct identified-workflow workflow-descriptor (identity) #:transparent)
(struct captured-workflow identified-workflow (build) #:transparent)
(define (workflow-add-fingerprint-suffix workflow suffix)
  (define updated
    (struct-copy workflow-descriptor workflow
      [fingerprint (string-append (workflow-descriptor-fingerprint workflow) suffix)]))
  (define fields
    (list (workflow-descriptor-name updated) (workflow-descriptor-version updated)
          (workflow-descriptor-fingerprint updated) (workflow-descriptor-stages updated)
          (workflow-descriptor-key updated) (workflow-descriptor-changes updated)))
  (cond [(captured-workflow? workflow)
         (apply captured-workflow (append fields (list (identified-workflow-identity workflow)
                                                       (captured-workflow-build workflow))))]
        [(identified-workflow? workflow)
         (apply identified-workflow (append fields (list (identified-workflow-identity workflow))))]
        [else updated]))
(define (workflow-invocation-key workflow arguments)
  (define (compute)
    (or (current-workflow-invocation-key)
        (and (workflow-descriptor-key workflow) ((workflow-descriptor-key workflow) arguments))))
  (if (captured-workflow? workflow)
      (call-with-executable-build (captured-workflow-build workflow) compute)
      (compute)))
(define (make-workflow name version fingerprint stages #:key [key #f] #:changes [changes (lambda (_arguments _result) '())]
                       #:build-id [build-id (current-build-identity)])
  (set! build-id (normalize-build-identity build-id))
  (define codecs (check-workflow-program! name version fingerprint stages key changes))
  (define executable-fingerprint
    (if (null? codecs) fingerprint
        (string-append fingerprint ":codecs:" (json->string (for/list ([codec (in-list codecs)])
                                                             (hasheq 'name (value-codec-name codec) 'version (value-codec-version codec) 'schema (value-codec-schema codec)))))))
  (cond [(current-executable-build)
         (captured-workflow name version executable-fingerprint stages key changes build-id (current-executable-build))]
        [build-id (identified-workflow name version executable-fingerprint stages key changes build-id)]
        [else (workflow-descriptor name version executable-fingerprint stages key changes)]))
(define (workflow-executable-fingerprint workflow adapters)
  (define own-identity (and (identified-workflow? workflow) (identified-workflow-identity workflow)))
  (define runtime-identity (current-build-identity))
  (when (and own-identity runtime-identity (not (equal? own-identity runtime-identity)))
    (error 'workflow "workflow and runtime declare conflicting build identities"))
  (define fingerprint
    (if (captured-workflow? workflow)
        (string-append (workflow-descriptor-fingerprint workflow) ":build:"
                       (executable-build-fingerprint (captured-workflow-build workflow)))
        (workflow-descriptor-fingerprint workflow)))
  (define names (sort (remove-duplicates
    (for/list ([stage (in-list (workflow-descriptor-stages workflow))] #:when (eq? (workflow-stage-kind stage) 'effect))
      (workflow-stage-adapter stage))) symbol<?))
  (define versions
    (for/list ([name (in-list names)]
               #:do [(define adapter (hash-ref adapters name #f))]
               #:when (versioned-effect-adapter? adapter))
      (list (symbol->string name) (symbol->string (effect-adapter-policy adapter)) (versioned-effect-adapter-version adapter))))
  (bind-build-identity
    (if (null? versions) fingerprint
        (string-append fingerprint ":adapters:" (json->string versions)))
    (or own-identity runtime-identity)))
(define (call-with-workflow-build workflow thunk)
  (if (captured-workflow? workflow)
      (call-with-executable-build (captured-workflow-build workflow) thunk)
      (thunk)))
