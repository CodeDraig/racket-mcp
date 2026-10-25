#lang racket/base
(require "private/persistent-json.rkt" "private/json-equality.rkt" "private/failure.rkt" "clock.rkt"
         racket/list
         racket/match
         "storage.rkt"
         "json.rkt"
         "schema.rkt"
         "error.rkt"
         "codec.rkt"
         "freshness.rkt"
         "effect.rkt"
         "private/input-response.rkt"
         "private/elicitation-schema.rkt"
         "private/workflow-types.rkt"
         "private/workflow-contract.rkt"
         "private/workflow-context.rkt"
         "private/workflow-definition.rkt"
         "private/workflow-changes.rkt"
         "private/workflow-recovery.rkt")
(provide (struct-out workflow-descriptor) (struct-out workflow-stage) (all-from-out "effect.rkt") workflow-executable-fingerprint
         make-workflow run-workflow recover-workflow!
         current-workflow-change-publisher current-workflow-store current-workflow-adapters current-workflow-state current-workflow-responses current-workflow-invocation-key
         (struct-out exn:fail:recovery))

;; Stage arbitration and the worker claim stay together: host computation runs
;; outside SQLite, while each durable transition commits before its successor.
(define (run-workflow workflow store arguments #:principal principal #:state [handle #f]
                      #:responses [responses (hasheq)] #:adapters [adapters (hasheq)]
                      #:clock [clock mcp-current-seconds] #:ttl [ttl 86400] #:cancelled? [cancelled? (lambda () #f)])
  (check-workflow-descriptor! workflow 'run-workflow)
  (define requested-handoff (current-workflow-task-handoff))
  (define (run)
    ;; The entry point names one workflow. Nested local workflows must not
    ;; inherit its task factory or hand their state to the parent's operation.
    (parameterize ([current-workflow-task-handoff
                    (and (pair? requested-handoff) (eq? (car requested-handoff) workflow)
                         (cdr requested-handoff))])
      (run-workflow/core workflow store arguments #:principal principal #:state handle
                         #:responses responses #:adapters adapters #:clock clock
                         #:ttl ttl #:cancelled? cancelled?)))
  (call-with-workflow-build workflow run))
(define (run-workflow/core workflow store arguments #:principal principal #:state [handle #f]
                      #:responses [responses (hasheq)] #:adapters [adapters (hasheq)]
                      #:clock [clock mcp-current-seconds] #:ttl [ttl 86400] #:cancelled? [cancelled? (lambda () #f)])
  (define executable-fingerprint (workflow-executable-fingerprint workflow adapters))
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'run-workflow "workflow execution must own its storage transaction boundaries"))
  (unless (and (or (not handle) (string? handle)) (hash? responses)) (mcp-error -32602 "Invalid continuation parameters"))
  (set! arguments (for/hasheq ([(key value) (in-hash arguments)] #:unless (missing? value)) (values key value)))
  (define invocation-key (and (not handle) (workflow-invocation-key workflow arguments)))
  (set! arguments (persistent-json arguments))
  ;; MRTR recommends ignoring unrecognized input-response fields. Known inputs
  ;; from another round are different: accepting those would bypass its boundary.
  (define (stage-inputs stage)
    (case (workflow-stage-kind stage)
      [(input) (list (workflow-stage-id stage))]
      [(input-group) (workflow-stage-adapter stage)]
      [else '()]))
  (define input-ids (append-map stage-inputs (workflow-descriptor-stages workflow)))
  (when (for/or ([id (in-list input-ids)]) (hash-has-key? arguments id))
    (error 'run-workflow "input identity collides with an argument"))
  (set! responses (for/hasheq ([(id response) (in-hash responses)] #:when (memq id input-ids)) (values id response)))
  (when (and (not handle) (positive? (hash-count responses))) (mcp-error -32602 "Input responses require a continuation"))
  (define round (and handle (resolve-continuation store handle)))
  (define round-stage (and round (findf (lambda (stage) (eq? (workflow-stage-id stage) (cdr round))) (workflow-descriptor-stages workflow))))
  (when (and round (for/or ([id (in-hash-keys responses)]) (not (and round-stage (memq id (stage-inputs round-stage))))))
    (mcp-error -32602 "Input response belongs to a different continuation round"))
  (define instance
    (if handle (or (load-instance store (if round (car round) handle)) (mcp-error -32602 "Unknown continuation"))
        (create-instance! store principal (workflow-descriptor-name workflow) arguments
                          (workflow-descriptor-version workflow) executable-fingerprint (+ (clock) ttl)
                          (hasheq 'position 0 'values arguments 'status "working" 'effects (hasheq))
                          #:key invocation-key)))
  (unless (and (equal? principal (stored-instance-principal instance))
               (equal? arguments (stored-instance-arguments instance))
               (equal? (workflow-descriptor-name workflow) (stored-instance-operation instance)))
    (error 'run-workflow "continuation does not belong to this principal, operation, and arguments"))
  (when (<= (stored-instance-expires instance) (clock)) (error 'run-workflow "continuation expired"))
  (unless (and (equal? (workflow-descriptor-version workflow) (stored-instance-version instance))
               (equal? executable-fingerprint (stored-instance-fingerprint instance)))
    (recovery instance #f "workflow code is incompatible with saved execution"))
  (define (decoded-env env)
    (for/fold ([decoded env]) ([stage (in-list (workflow-descriptor-stages workflow))]
                              #:when (and (value-codec? (workflow-stage-schema stage)) (hash-has-key? env (workflow-stage-id stage))))
      (hash-set decoded (workflow-stage-id stage) (decode-value (workflow-stage-schema stage) (hash-ref env (workflow-stage-id stage))))))
  (define (prepare-value stage value)
    (define keys '())
    (when (committed-result? value)
      (unless (eq? (workflow-stage-kind stage) 'effect) (error 'workflow "commit acknowledgements belong to effect stages"))
      (set! keys (committed-result-keys value))
      (set! value (committed-result-result value)))
    (define schema (workflow-stage-schema stage))
    (when (value-codec? schema) (set! value (encode-value schema value)))
    (unless (and (json-value? value) (valid? (if (value-codec? schema) (codec-storage-schema schema) schema) value)) (error 'run-workflow "stage ~a failed its codec schema" (workflow-stage-id stage)))
    (values value keys))
  (define (advance! current stage value)
    (define-values (encoded keys) (prepare-value stage value))
    (advance-prepared! current stage encoded keys))
  (define (advance-prepared! current stage value keys)
    (define state (stored-instance-state current))
    (define next (hash-set* (hash-remove (hash-remove state 'pending-input) 'pending-group) 'position (add1 (hash-ref state 'position)) 'status "working"
                           'values (hash-set (hash-ref state 'values) (workflow-stage-id stage) value)))
    (record-event! store (stored-instance-handle current) (hasheq 'kind "stage-completed" 'stage (symbol->string (workflow-stage-id stage))))
    (record-workflow-changes! store principal keys #:handle (stored-instance-handle current) #:stage (workflow-stage-id stage))
    (update-instance! store current next))
  (define (execute)
  (let loop ()
    (when (cancelled?) (error 'run-workflow "execution cancelled"))
    ;; A transaction arbitrates each stage independently; another retry can only
    ;; observe committed state. External effects deliberately release it.
    (define action
      (store-transaction store
        (lambda ()
          (set! instance (load-instance store (stored-instance-handle instance)))
          (define state (stored-instance-state instance))
          (define position (hash-ref state 'position))
          ;; Validate again under the transition transaction: another request
          ;; may have accepted this response since the initial ownership check.
          (for ([(id response) (in-hash responses)])
            (define saved (hash-ref (hash-ref state 'values) id missing))
            (cond [(not (missing? saved))
                   (unless (json-value=? saved response) (mcp-error -32602 "Conflicting response for completed input"))]
                  [else
                   (unless (and (< position (length (workflow-descriptor-stages workflow)))
                                (let ([stage (list-ref (workflow-descriptor-stages workflow) position)])
                                  (memq id (stage-inputs stage))))
                     (mcp-error -32602 "Response does not match a pending input"))]))
          (cond [(and (current-workflow-task-handoff) (hash-has-key? state 'task-handoff))
                 (list 'task-handoff instance)]
                [(member (hash-ref state 'status) '("completed" "abandoned")) (list 'return (hash-ref state 'result))]
                [(>= position (length (workflow-descriptor-stages workflow))) (error 'run-workflow "workflow has no completion stage")]
                [else
                 (define stage (list-ref (workflow-descriptor-stages workflow) position))
                 (define id (workflow-stage-id stage))
                 (define env (hash-ref state 'values))
                 (define pending-key (if (eq? (workflow-stage-kind stage) 'input-group) 'pending-group 'pending-input))
                 (case (if (and (memq (workflow-stage-kind stage) '(input input-group))
                                (not (hash-has-key? state pending-key)))
                           'prepare-input (workflow-stage-kind stage))
                   [(prepare-input) (list 'prepare-input stage env instance pending-key)]
                   [(task-boundary)
                    (if (current-workflow-task-handoff)
                        (list 'task-handoff instance)
                        (begin
                          ;; Boundary identities name control-flow stages, not
                          ;; persistent values; never overwrite an argument.
                          (record-event! store (stored-instance-handle instance)
                                         (hasheq 'kind "task-boundary" 'stage (symbol->string id)))
                          (update-instance! store instance (hash-set state 'position (add1 position)))
                          (list 'continue)))]
                   [(jump branch complete checkpoint)
                    (list (workflow-stage-kind stage) stage env instance)]
                   [(input-group)
                    (define ids (stage-inputs stage))
                    (define requests (hash-ref state 'pending-group))
                    (unless (and (hash? requests) (= (hash-count requests) (length ids))
                                 (andmap (lambda (id) (hash-has-key? requests id)) ids))
                      (error 'run-workflow "input group requests do not match declared identities"))
                    (define accepted
                      (for/fold ([saved env]) ([input-id (in-list ids)] #:when (hash-has-key? responses input-id))
                        (define response (hash-ref responses input-id))
                        (validate-input-response (hash-ref requests input-id) response)
                        (unless (valid? (hash-ref (hash-ref (workflow-stage-schema stage) 'properties) input-id) response)
                          (mcp-error -32602 "Input response failed its declared representation"))
                        (unless (hash-has-key? env input-id)
                          (record-event! store (stored-instance-handle instance)
                                         (hasheq 'kind "input-accepted" 'stage (symbol->string id) 'input (symbol->string input-id))))
                        (hash-set saved input-id response)))
                    (define waiting (filter (lambda (input-id) (not (hash-has-key? accepted input-id))) ids))
                    (define updated (update-instance! store instance (hash-set* state 'pending-group requests 'values accepted 'status "input_required")))
                    (cond [(null? waiting)
                           (advance! updated stage (for/hasheq ([input-id (in-list ids)]) (values input-id (hash-ref accepted input-id))))
                           '(continue)]
                          [else
                           (list 'return
                                 (hasheq 'resultType "input_required" 'requestState (continuation-token! store (stored-instance-handle instance) id)
                                         'inputRequests (for/hasheq ([input-id (in-list waiting)])
                                                          (values input-id (hasheq 'method "elicitation/create" 'params (hash-ref requests input-id))))))])]
                   [(input)
                    (define response (hash-ref responses id missing))
                    (cond [(missing? response)
                           (define request (hash-ref state 'pending-input))
                           (update-instance! store instance (hash-set* state 'status "input_required" 'pending-input request))
                           (list 'return (hasheq 'resultType "input_required" 'requestState (continuation-token! store (stored-instance-handle instance) id)
                                                'inputRequests (hasheq id (hasheq 'method "elicitation/create" 'params request))))]
                          [else
                           (define request (hash-ref state 'pending-input))
                           (validate-input-response request response)
                           (advance! instance stage response) '(continue)])]
                   [(effect)
                    (define adapter (hash-ref adapters (workflow-stage-adapter stage) (lambda () (error 'run-workflow "missing effect adapter ~a" (workflow-stage-adapter stage)))))
                    (unless (eq? (effect-adapter-policy adapter) (workflow-stage-policy stage)) (error 'run-workflow "effect policy mismatch"))
                    (define effects (hash-ref state 'effects))
                    (define prior (hash-ref effects id #f))
                    (define key (if prior (hash-ref prior 'key) (opaque-handle)))
                    (when (and prior (eq? (effect-adapter-policy adapter) 'manual)
                               (not (equal? (hash-ref prior 'status) "retry-authorized")))
                      (recovery instance id "external effect outcome is uncertain; inspect and record an outcome or authorize retry"))
                    (list 'prepare-effect stage env instance adapter key)])]))))
    (publish-workflow-changes!)
    (case (car action)
      [(task-handoff) ((current-workflow-task-handoff) (cadr action))]
      [(return) (cadr action)] [(continue) (loop)]
      [(prepare-input)
       (match-define (list _ stage env snapshot pending-key) action)
       (define requests ((workflow-stage-procedure stage) (decoded-env env)))
       (when (eq? (workflow-stage-kind stage) 'input-group)
         (define ids (stage-inputs stage))
         (unless (and (hash? requests) (= (hash-count requests) (length ids))
                      (andmap (lambda (id) (hash-has-key? requests id)) ids))
           (error 'run-workflow "input group requests do not match declared identities")))
       (for ([request (in-list (if (eq? (workflow-stage-kind stage) 'input-group)
                                  (hash-values requests) (list requests)))])
         (unless (elicitation-request-valid? request)
           (error 'run-workflow "invalid elicitation request at stage ~a" (workflow-stage-id stage))))
       (store-transaction store
         (lambda ()
           (when (cancelled?) (error 'run-workflow "execution cancelled"))
           (update-instance! store snapshot (hash-set (stored-instance-state snapshot) pending-key requests))))
       (loop)]
      [(jump branch complete)
       (match-define (list kind stage env snapshot) action)
       ;; The worker claim protects this stage while host code runs without
       ;; SQLite's transaction. Cancellation must win before committing it.
       (define value ((workflow-stage-procedure stage) (decoded-env env)))
       (define id (workflow-stage-id stage))
       (define state (stored-instance-state snapshot))
       (define destination
         (case kind
           [(jump) (index-of (map workflow-stage-id (workflow-descriptor-stages workflow)) (workflow-stage-adapter stage))]
           [(branch)
            (define targets (workflow-stage-adapter stage))
            (unless (and (exact-nonnegative-integer? value) (< value (length targets)))
              (error 'run-workflow "invalid branch selector"))
            (index-of (map workflow-stage-id (workflow-descriptor-stages workflow)) (list-ref targets value))]
           [else #f]))
       (define changes
         (cond [(eq? kind 'complete)
                (unless (valid? (workflow-stage-schema stage) value) (error 'run-workflow "invalid completion"))
                (if (and (hash? value) (hash-ref value 'isError #f)) '()
                    ((workflow-descriptor-changes workflow) arguments value))]
               [else '()]))
       (store-transaction store
         (lambda ()
           (when (cancelled?) (error 'run-workflow "execution cancelled"))
           (case kind
             [(jump)
              (update-instance! store snapshot (hash-set state 'position destination))
              (record-event! store (stored-instance-handle snapshot) (hasheq 'kind "join" 'stage (symbol->string id)))]
             [(branch)
              (unless destination (error 'run-workflow "unresolved branch destination"))
              (update-instance! store snapshot (hash-set* state 'position destination 'values (hash-set env id value)))
              (record-event! store (stored-instance-handle snapshot) (hasheq 'kind "branch" 'stage (symbol->string id) 'selection value))]
             [(complete)
              (record-workflow-changes! store principal changes #:handle (stored-instance-handle snapshot) #:stage id)
              (update-instance! store snapshot (hash-set* state 'status "completed" 'result value))])))
       (publish-workflow-changes!)
       (if (eq? kind 'complete) value (loop))]
      [(checkpoint)
       (match-define (list _ stage env snapshot) action)
       ;; Replay-safe host computation may block. Keep the instance worker claim,
       ;; but release SQLite so polling, cancellation, and other instances proceed.
       (define value ((workflow-stage-procedure stage) (decoded-env env)))
       (define-values (encoded keys) (prepare-value stage value))
       (store-transaction store
         (lambda ()
           (when (cancelled?) (error 'run-workflow "execution cancelled"))
           (advance-prepared! snapshot stage encoded keys)))
       (loop)]
      [(prepare-effect)
       (match-define (list _ stage env snapshot adapter key) action)
       (define input ((workflow-stage-procedure stage) (decoded-env env)))
       (define id (workflow-stage-id stage))
       (define state (stored-instance-state snapshot))
       (define position (hash-ref state 'position))
       (cond
         [(eq? (effect-adapter-policy adapter) 'transactional)
          (store-transaction store
            (lambda ()
              (when (cancelled?) (error 'run-workflow "execution cancelled"))
              (define result ((effect-adapter-invoke adapter) input key (current-store-connection)))
              (advance! snapshot stage result)))]
         [else
          (store-transaction store
            (lambda ()
              (when (cancelled?) (error 'run-workflow "execution cancelled"))
              (define schema (workflow-stage-schema stage))
              (define intent
                (hasheq 'key key 'status "intent" 'position position
                        'schema (if (value-codec? schema) (codec-storage-schema schema) schema)
                        'codec (if (value-codec? schema)
                                   (hasheq 'name (value-codec-name schema) 'version (value-codec-version schema)) #f)))
              (update-instance! store snapshot (hash-set state 'effects (hash-set (hash-ref state 'effects) id intent)))
              (record-event! store (stored-instance-handle snapshot) (hasheq 'kind "effect-intent" 'stage (symbol->string id) 'key key))))
          (define result ((effect-adapter-invoke adapter) input key #f))
          (define-values (encoded keys) (prepare-value stage result))
          (store-transaction store
            (lambda ()
              (define current (load-instance store (stored-instance-handle snapshot)))
              (when (= (hash-ref (stored-instance-state current) 'position) position)
                (advance-prepared! current stage encoded keys))))])
       (publish-workflow-changes!)
       (loop)])))
  ;; The database transaction protects each transition; this separate claim
  ;; spans external adapter execution without holding a database transaction.
  (define result missing)
  (define observer (current-workflow-failure-observer))
  (let claim-loop ()
    (when (cancelled?) (error 'run-workflow "execution cancelled"))
    (when (<= (stored-instance-expires instance) (clock)) (error 'run-workflow "continuation expired"))
    ;; A recorded handoff is a receipt, independent of the now-running task's
    ;; workflow claim. Still execute the transactional response/conflict checks.
    (unless (if (and (current-workflow-task-handoff)
                     (hash-has-key? (stored-instance-state (load-instance store (stored-instance-handle instance))) 'task-handoff))
                (begin (set! result (execute)) #t)
                (call-with-instance-worker store (stored-instance-handle instance)
                  (lambda () (with-handlers ([non-break-failure?
                    (lambda (failure)
                      (with-handlers ([non-break-failure? void])
                        (observer workflow store (load-instance store (stored-instance-handle instance)) failure))
                      (raise failure))]) (set! result (execute))))))
      (sync (alarm-evt (+ (current-inexact-milliseconds) 25)))
      (claim-loop)))
  result)
(define current-workflow-failure-observer (make-parameter (lambda (_workflow _store _flow _failure) (void))))
(module+ private (provide workflow-rename current-workflow-failure-observer workflow-add-fingerprint-suffix current-workflow-task-handoff workflow-invocation-key))
