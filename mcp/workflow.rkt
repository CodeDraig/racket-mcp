#lang racket/base
(require racket/list racket/match "storage.rkt" "json.rkt" "schema.rkt" "descriptor.rkt")
(provide (struct-out workflow-descriptor) (struct-out workflow-stage) (struct-out effect-adapter)
         make-workflow run-workflow recover-workflow!
         current-workflow-store current-workflow-adapters current-workflow-state current-workflow-responses
         (struct-out exn:fail:recovery))
;; Stage procedures receive persistent JSON environments. Their result is saved
;; before the next stage runs. Only named adapters may cross effect boundaries.
(struct workflow-stage (id kind schema procedure adapter policy) #:transparent)
(struct workflow-descriptor (name version fingerprint stages key) #:transparent)
(struct effect-adapter (policy invoke) #:transparent)
(struct exn:fail:recovery exn:fail (handle stage) #:transparent)
(define current-workflow-store (make-parameter #f))
(define current-workflow-adapters (make-parameter (hasheq)))
(define current-workflow-state (make-parameter #f))
(define current-workflow-responses (make-parameter (hasheq)))
(define (recovery instance stage message)
  (raise (exn:fail:recovery message (current-continuation-marks) (stored-instance-handle instance) stage)))
(define (make-workflow name version fingerprint stages #:key [key #f])
  (unless (= (length stages) (length (remove-duplicates (map workflow-stage-id stages)))) (error 'make-workflow "duplicate stage IDs"))
  (for ([s (in-list stages)])
    (unless (memq (workflow-stage-kind s) '(checkpoint input effect complete branch)) (error 'make-workflow "invalid stage kind"))
    (check-schema! (workflow-stage-schema s)))
  (workflow-descriptor name version fingerprint stages key))
(define (run-workflow workflow store arguments #:principal principal #:state [handle #f]
                      #:responses [responses (hasheq)] #:adapters [adapters (hasheq)]
                      #:clock [clock current-seconds] #:ttl [ttl 86400] #:cancelled? [cancelled? (lambda () #f)])
  (define instance
    (if handle (or (load-instance store handle) (error 'run-workflow "unknown continuation"))
        (create-instance! store principal (workflow-descriptor-name workflow) arguments
                          (workflow-descriptor-version workflow) (workflow-descriptor-fingerprint workflow) (+ (clock) ttl)
                          (hasheq 'position 0 'values arguments 'status "working" 'effects (hasheq))
                          #:key (and (workflow-descriptor-key workflow) ((workflow-descriptor-key workflow) arguments)))))
  (unless (and (equal? principal (stored-instance-principal instance))
               (equal? arguments (stored-instance-arguments instance))
               (equal? (workflow-descriptor-name workflow) (stored-instance-operation instance)))
    (error 'run-workflow "continuation does not belong to this principal, operation, and arguments"))
  (when (<= (stored-instance-expires instance) (clock)) (error 'run-workflow "continuation expired"))
  (unless (and (equal? (workflow-descriptor-version workflow) (stored-instance-version instance))
               (equal? (workflow-descriptor-fingerprint workflow) (stored-instance-fingerprint instance)))
    (recovery instance #f "workflow code is incompatible with saved execution"))
  (define (advance! current stage value)
    (unless (valid? (workflow-stage-schema stage) value) (error 'run-workflow "stage ~a failed its codec schema" (workflow-stage-id stage)))
    (define state (stored-instance-state current))
    (define next (hash-set* (hash-remove state 'pending-input) 'position (add1 (hash-ref state 'position)) 'status "working"
                           'values (hash-set (hash-ref state 'values) (workflow-stage-id stage) value)))
    (record-event! store (stored-instance-handle current) (hasheq 'kind "stage-completed" 'stage (symbol->string (workflow-stage-id stage))))
    (update-instance! store current next))
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
          (cond [(member (hash-ref state 'status) '("completed" "abandoned")) (list 'return (hash-ref state 'result))]
                [(>= position (length (workflow-descriptor-stages workflow))) (error 'run-workflow "workflow has no completion stage")]
                [else
                 (define stage (list-ref (workflow-descriptor-stages workflow) position))
                 (define id (workflow-stage-id stage))
                 (define env (hash-ref state 'values))
                 (case (workflow-stage-kind stage)
                   [(branch)
                    (define selection ((workflow-stage-procedure stage) env))
                    (define targets (workflow-stage-adapter stage))
                    (unless (and (exact-nonnegative-integer? selection) (< selection (length targets))) (error 'run-workflow "invalid branch selector"))
                    (define destination (index-of (map workflow-stage-id (workflow-descriptor-stages workflow)) (list-ref targets selection)))
                    (unless destination (error 'run-workflow "unresolved branch destination"))
                    (update-instance! store instance (hash-set* state 'position destination 'values (hash-set env id selection)))
                    (record-event! store (stored-instance-handle instance) (hasheq 'kind "branch" 'stage (symbol->string id) 'selection selection))
                    '(continue)]
                   [(complete)
                    (define result ((workflow-stage-procedure stage) env))
                    (unless (valid? (workflow-stage-schema stage) result) (error 'run-workflow "invalid completion"))
                    (update-instance! store instance (hash-set* state 'status "completed" 'result result)) (list 'return result)]
                   [(checkpoint) (advance! instance stage ((workflow-stage-procedure stage) env)) '(continue)]
                   [(input)
                    (define response (hash-ref responses id missing))
                    (cond [(missing? response)
                           (define request (hash-ref state 'pending-input (lambda () ((workflow-stage-procedure stage) env))))
                           (update-instance! store instance (hash-set* state 'status "input_required" 'pending-input request))
                           (list 'return (hasheq 'resultType "input_required" 'requestState (stored-instance-handle instance)
                                                'inputRequests (hasheq id (hasheq 'method "elicitation/create" 'params request))))]
                          [else
                           (unless (and (hash? response) (member (hash-ref response 'action #f) '("accept" "decline" "cancel")))
                             (error 'run-workflow "invalid elicitation response action"))
                           (define request (hash-ref state 'pending-input (lambda () ((workflow-stage-procedure stage) env))))
                           (when (and (equal? (hash-ref response 'action) "accept") (equal? (hash-ref request 'mode "form") "form")
                                      (not (valid? (hash-ref request 'requestedSchema) (hash-ref response 'content json-null))))
                             (error 'run-workflow "elicitation content failed the requested schema"))
                           (advance! instance stage response) '(continue)])]
                   [(effect)
                    (define adapter (hash-ref adapters (workflow-stage-adapter stage) (lambda () (error 'run-workflow "missing effect adapter ~a" (workflow-stage-adapter stage)))))
                    (unless (eq? (effect-adapter-policy adapter) (workflow-stage-policy stage)) (error 'run-workflow "effect policy mismatch"))
                    (define effects (hash-ref state 'effects))
                    (define prior (hash-ref effects id #f))
                    (define key (if prior (hash-ref prior 'key) (opaque-handle)))
                    (define input ((workflow-stage-procedure stage) env))
                    (cond [(eq? (effect-adapter-policy adapter) 'transactional)
                           (define result ((effect-adapter-invoke adapter) input key (current-store-connection)))
                           (advance! instance stage result) '(continue)]
                          [(and prior (eq? (effect-adapter-policy adapter) 'manual) (not (equal? (hash-ref prior 'status) "retry-authorized")))
                           (recovery instance id "external effect outcome is uncertain; inspect and record an outcome or authorize retry")]
                          [else
                           (update-instance! store instance (hash-set state 'effects (hash-set effects id (hasheq 'key key 'status "intent" 'position position 'schema (workflow-stage-schema stage)))))
                           (record-event! store (stored-instance-handle instance) (hasheq 'kind "effect-intent" 'stage (symbol->string id) 'key key))
                           (list 'effect stage adapter input key)])])]))))
    (case (car action)
      [(return) (cadr action)] [(continue) (loop)]
      [(effect)
       (match-define (list _ stage adapter input key) action)
       (define result ((effect-adapter-invoke adapter) input key #f))
       (store-transaction store
         (lambda ()
           (define current (load-instance store (stored-instance-handle instance)))
           (when (= (hash-ref (stored-instance-state current) 'position) (hash-ref (stored-instance-state instance) 'position))
             (advance! current stage result))))
       (loop)])))
(define (recover-workflow! store handle stage action #:outcome [outcome missing] #:principal principal)
  (store-transaction store
    (lambda ()
      (define instance (or (load-instance store handle) (error 'recover-workflow! "unknown handle")))
      (unless (equal? principal (stored-instance-principal instance)) (error 'recover-workflow! "foreign handle"))
      (define state (stored-instance-state instance))
      (unless (equal? (hash-ref state 'status) "working") (error 'recover-workflow! "execution is not recoverable"))
      (define effects (hash-ref state 'effects))
      (define intent (hash-ref effects stage (lambda () (error 'recover-workflow! "no effect intent"))))
      (unless (= (hash-ref state 'position) (hash-ref intent 'position)) (error 'recover-workflow! "effect is not the current stage"))
      (define next
        (case action
          [(outcome) (when (or (missing? outcome) (not (valid? (hash-ref intent 'schema) outcome))) (error 'recover-workflow! "valid outcome required"))
                     (hash-set* state 'position (add1 (hash-ref state 'position)) 'values (hash-set (hash-ref state 'values) stage outcome))]
          [(retry) (hash-set state 'effects (hash-set effects stage (hash-set intent 'status "retry-authorized")))]
          [(abandon) (hash-set* state 'status "abandoned" 'result (error-result "Execution abandoned during recovery"))]
          [else (error 'recover-workflow! "unknown recovery action")]))
      (record-event! store handle (hasheq 'kind "recovery" 'stage (symbol->string stage) 'action (symbol->string action)))
      (update-instance! store instance next))))
