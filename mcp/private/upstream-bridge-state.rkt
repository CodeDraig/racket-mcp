#lang racket/base
(require file/sha1
         (submod "../build.rkt" private)
         "../storage.rkt"
         "../json.rkt"
         "../clock.rkt"
         "../error.rkt"
         "elicitation-schema.rkt")
(provide (struct-out upstream-bridge) (struct-out exn:fail:upstream-recovery) current-upstream-task-result
         make-upstream-bridge freeze save-state! uncertain owned normalize-outcome record-outcome! local-outcome fingerprint check-binding!)
(struct upstream-bridge (identity version credential-id ttl max-rounds max-bytes) #:transparent)
(struct exn:fail:upstream-recovery exn:fail (handle cause) #:transparent)
(define current-upstream-task-result (make-parameter #f))
(define (make-upstream-bridge #:identity identity #:version version #:credential-id credential-id
                              #:ttl [ttl 86400] #:max-rounds [rounds 100] #:max-bytes [bytes 1048576])
  (unless (and (string? identity) (positive? (string-length identity))
               (string? version) (positive? (string-length version)))
    (error 'make-upstream-bridge "identity and version must be nonempty strings"))
  (unless (and (procedure? credential-id) (procedure-arity-includes? credential-id 1))
    (error 'make-upstream-bridge "credential-id must accept the local principal"))
  (unless (andmap exact-positive-integer? (list ttl rounds bytes))
    (error 'make-upstream-bridge "limits must be positive integers"))
  (upstream-bridge (string->immutable-string identity) (string->immutable-string version) credential-id ttl rounds bytes))
(define (freeze bridge value)
  (define encoded (json->string value))
  (when (> (bytes-length (string->bytes/utf-8 encoded)) (upstream-bridge-max-bytes bridge))
    (error 'upstream "bridge value exceeds configured byte limit"))
  (string->json encoded))
(define (save-state! bridge store instance state)
  (update-instance! store instance (freeze bridge state)))
(define (uncertain instance [cause #f])
  (raise (exn:fail:upstream-recovery "Upstream outcome is uncertain; explicit recovery is required"
                                    (current-continuation-marks) (stored-instance-handle instance) cause)))
(define (owned store handle principal)
  (define instance (or (load-instance store handle) (mcp-error -32602 "Unknown upstream interaction")))
  (unless (and (equal? principal (stored-instance-principal instance))
               (equal? (hash-ref (stored-instance-state instance) 'kind #f) "upstream"))
    (mcp-error -32602 "Unknown or foreign upstream interaction"))
  (when (<= (stored-instance-expires instance) (mcp-current-seconds))
    (mcp-error -32602 "Upstream interaction expired"))
  instance)
(define (normalize-outcome value)
  (unless (hash? value) (error 'upstream "expected an object outcome"))
  (cond [(and (not (hash-has-key? value 'resultType)) (hash-has-key? value 'error))
         (unless (hash? (hash-ref value 'error)) (error 'upstream "malformed upstream error"))
         (hasheq 'error (hash-ref value 'error))]
        [else
         (define result (if (hash-has-key? value 'resultType) value (hash-ref value 'result value)))
         (unless (hash? result) (error 'upstream "expected an object result"))
         (hasheq 'result (hash-set result 'resultType (hash-ref result 'resultType "complete")))]))
;; Called under a transaction after a known response, including operator recovery.
(define (record-outcome! bridge store instance outcome)
  (define state (hash-remove (stored-instance-state instance) 'observed-outcome))
  (define result (hash-ref outcome 'result #f))
  (define pending? (and result (equal? (hash-ref result 'resultType) "input_required")))
  (define next
    (cond
      [pending?
       (unless (and (or (hash-has-key? result 'requestState) (hash-has-key? result 'inputRequests))
                    (or (not (hash-has-key? result 'requestState)) (string? (hash-ref result 'requestState)))
                    (hash? (hash-ref result 'inputRequests (hasheq))))
         (error 'upstream "malformed input-required result"))
       (define requests (hash-ref result 'inputRequests (hasheq)))
       (for ([(id request) (in-hash requests)])
         (unless (and (hash? request) (equal? (hash-ref request 'method #f) "elicitation/create")
                      (elicitation-request-valid? (hash-ref request 'params #f)))
           (error 'upstream "bridge requires a valid elicitation input request")))
       (define round (add1 (hash-ref state 'round)))
       (when (> round (upstream-bridge-max-rounds bridge)) (error 'upstream "bridge round limit exceeded"))
       (define mapping
         (for/hasheq ([(remote request) (in-hash requests)])
           (values (string->symbol (opaque-handle)) (hasheq 'remote (symbol->string remote) 'request request))))
       (define token (continuation-token! store (stored-instance-handle instance) (string->symbol (number->string round))))
       (hash-set* state 'status "input_required" 'round round 'remote result 'token token
                  'mapping mapping 'accepted (hasheq))]
      [else (hash-set* state 'status "complete" 'outcome outcome)]))
  (record-event! store (stored-instance-handle instance) (hasheq 'kind "upstream-response" 'round (hash-ref state 'round)))
  (save-state! bridge store instance next))
(define (local-outcome state capabilities)
  (cond [(equal? (hash-ref state 'status) "complete")
         (define outcome (hash-ref state 'outcome))
         (when (and (hash-has-key? outcome 'result)
                    (not (equal? (hash-ref (hash-ref outcome 'result) 'resultType) "complete")))
           (mcp-error -32603 "Upstream result type requires unsupported translation; the recorded outcome is retained for inspection"))
         outcome]
        [else
         (unless (or (zero? (hash-count (hash-ref state 'mapping))) (hash-has-key? capabilities 'elicitation))
           (mcp-error -32021 "Client elicitation capability is required"
                      (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
         (hasheq 'result
           (hasheq 'resultType "input_required" 'requestState (hash-ref state 'token)
                   'inputRequests
                   (for/hasheq ([(id entry) (in-hash (hash-ref state 'mapping))]
                               #:unless (hash-has-key? (hash-ref state 'accepted) id))
                     (values id (hash-ref entry 'request)))))]))
(define (fingerprint bridge snapshot)
  (bind-build-identity
    (bytes->hex-string (sha256-bytes (open-input-string
      (json->string (hasheq 'snapshot snapshot 'bridge (upstream-bridge-identity bridge)
                           'version (upstream-bridge-version bridge))))))))
(define (check-binding! bridge snapshot instance credential arguments)
  (unless (and (equal? (stored-instance-version instance) "upstream/1")
               (equal? (stored-instance-fingerprint instance) (fingerprint bridge snapshot))
               (equal? (hash-ref (stored-instance-state instance) 'credential) credential)
               (equal? (stored-instance-arguments instance) arguments))
    (mcp-error -32602 "Upstream continuation does not match this binding, credential, or request")))
