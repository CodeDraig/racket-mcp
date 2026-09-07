#lang racket/base
(require racket/list file/sha1 "storage.rkt" "json.rkt" "clock.rkt" "error.rkt" "private/failure.rkt"
         "private/input-response.rkt" "private/elicitation-schema.rkt")
(provide make-upstream-bridge upstream-bridge? upstream-bridge-credential-id
         bridge-upstream-request recover-upstream-request!
         (struct-out exn:fail:upstream-recovery))
(struct upstream-bridge (identity version credential-id ttl max-rounds max-bytes) #:transparent)
(struct exn:fail:upstream-recovery exn:fail (handle cause) #:transparent)
(define current-upstream-task-result (make-parameter #f))
(module* private #f
  (provide current-upstream-task-result fingerprint freeze check-binding! upstream-bridge-identity upstream-bridge-max-rounds))
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
  (bytes->hex-string (sha256-bytes (open-input-string
    (json->string (hasheq 'snapshot snapshot 'bridge (upstream-bridge-identity bridge)
                         'version (upstream-bridge-version bridge)))))))
(define (check-binding! bridge snapshot instance credential arguments)
  (unless (and (equal? (stored-instance-version instance) "upstream/1")
               (equal? (stored-instance-fingerprint instance) (fingerprint bridge snapshot))
               (equal? (hash-ref (stored-instance-state instance) 'credential) credential)
               (equal? (stored-instance-arguments instance) arguments))
    (mcp-error -32602 "Upstream continuation does not match this binding, credential, or request")))
(define (bridge-upstream-request bridge store snapshot request method params
                                 #:principal principal #:credential-id credential
                                 #:state [token #f] #:responses [responses (hasheq)]
                                 #:capabilities [capabilities (hasheq)] #:key [key #f]
                                 #:verify [verify void]
                                 #:cancelled? [cancelled? (lambda () #f)])
  (unless (state-store? store) (error 'upstream "a configured bridge store is required"))
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'upstream "bridge requests must own their storage transaction boundaries"))
  (unless (and (string? credential) (positive? (string-length credential)))
    (error 'upstream "credential identity must be a nonempty string"))
  (unless (and (hash? params) (hash? responses) (or (not token) (string? token)))
    (mcp-error -32602 "Invalid bridge continuation parameters"))
  (unless (member method '("tools/call" "resources/read" "prompts/get"))
    (error 'upstream "this bridge supports tools, resource reads, and prompts"))
  (when (or (hash-has-key? params 'requestState) (hash-has-key? params 'inputResponses))
    (mcp-error -32602 "Pass local continuation fields through the bridge keywords"))
  (define arguments (freeze bridge (hasheq 'method method 'params params)))
  (set! responses (freeze bridge responses))
  (define resolved (and token (resolve-continuation store token)))
  (when (and token (not resolved)) (mcp-error -32602 "Unknown upstream continuation"))
  (when (and (not token) (positive? (hash-count responses)))
    (mcp-error -32602 "Upstream input responses require a continuation"))
  (define operation (string-append "upstream:" (upstream-bridge-identity bridge) ":" method))
  (define instance
    (if resolved (owned store (car resolved) principal)
        (create-instance! store principal operation arguments "upstream/1" (fingerprint bridge snapshot)
                          (+ (mcp-current-seconds) (upstream-bridge-ttl bridge))
                          (freeze bridge (hasheq 'kind "upstream" 'credential credential 'status "ready" 'round 0
                                                'history (hasheq) 'outgoing params)) #:key key)))
  (unless (equal? (stored-instance-operation instance) operation)
    (mcp-error -32602 "Upstream continuation belongs to another operation"))
  (check-binding! bridge snapshot instance credential arguments)
  (define handle (stored-instance-handle instance))
  (define (execute)
    (let loop ()
      (when (cancelled?) (error 'upstream "request cancelled"))
      (define action
        (store-transaction store
          (lambda ()
            (set! instance (owned store handle principal))
            (define state (stored-instance-state instance))
            (for ([(id response) (in-hash responses)] #:when (hash-has-key? (hash-ref state 'history) id))
              (unless (equal? response (hash-ref (hash-ref state 'history) id))
                (mcp-error -32602 "Conflicting upstream input response")))
            (case (string->symbol (hash-ref state 'status))
              [(complete)
               (define outcome (hash-ref state 'outcome))
               (list 'return
                 (if (and (current-upstream-task-result)
                          (equal? (hash-ref (hash-ref outcome 'result (hasheq)) 'resultType #f) "task"))
                     ((current-upstream-task-result) instance capabilities)
                     (local-outcome state capabilities)))]
              [(in-flight) (uncertain instance)]
              [(received)
               (record-outcome! bridge store instance (hash-ref state 'observed-outcome))
               (list 'again)]
              [(input_required)
               (define current-round (string->symbol (number->string (hash-ref state 'round))))
               (when (and resolved (not (eq? (cdr resolved) current-round))
                          (for/or ([id (in-hash-keys responses)]) (hash-has-key? (hash-ref state 'mapping) id)))
                 (mcp-error -32602 "Input response belongs to another upstream round"))
               (cond
                 [(not (and resolved (eq? (cdr resolved) current-round)))
                  (list 'return (local-outcome state capabilities))]
                 [else
                  (define accepted
                    (for/fold ([accepted (hash-ref state 'accepted)]) ([(id response) (in-hash responses)]
                                                                    #:when (hash-has-key? (hash-ref state 'mapping) id))
                      (define entry (hash-ref (hash-ref state 'mapping) id))
                      (validate-input-response (hash-ref (hash-ref entry 'request) 'params) response)
                      (hash-set accepted id response)))
                  (define history
                    (for/fold ([history (hash-ref state 'history)]) ([(id response) (in-hash accepted)])
                      (hash-set history id response)))
                  (define ready? (= (hash-count accepted) (hash-count (hash-ref state 'mapping))))
                  (define outgoing
                    (let* ([remote (hash-ref state 'remote)]
                           [base (hash-ref arguments 'params)]
                           [with-state (if (hash-has-key? remote 'requestState)
                                           (hash-set base 'requestState (hash-ref remote 'requestState)) base)])
                      (if (hash-has-key? remote 'inputRequests)
                          (hash-set with-state 'inputResponses
                            (for/hasheq ([(id response) (in-hash accepted)])
                              (values (string->symbol (hash-ref (hash-ref (hash-ref state 'mapping) id) 'remote)) response)))
                          with-state)))
                  (define saved
                    (save-state! bridge store instance
                      (hash-set* state 'accepted accepted 'history history
                                 'status (if ready? "ready" "input_required") 'outgoing outgoing)))
                  (if ready? (list 'again) (list 'return (local-outcome (stored-instance-state saved) capabilities)))])]
              [(ready)
               (list 'send (hash-ref state 'outgoing))]
              [else (error 'upstream "invalid stored bridge state")]))))
      (case (car action)
        [(return) (cadr action)]
        [(again) (loop)]
        [(send)
         (verify)
         (store-transaction store
           (lambda ()
             (when (cancelled?) (error 'upstream "request cancelled"))
             (define latest (owned store handle principal))
             (define state (stored-instance-state latest))
             (continuation-token! store handle (string->symbol (number->string (hash-ref state 'round))))
             (record-event! store handle (hasheq 'kind "upstream-intent" 'round (hash-ref state 'round)))
             (save-state! bridge store latest (hash-set state 'status "in-flight"))))
         ;; A thrown value, break, or process loss leaves the durable intent.
         ;; Never infer that failure means the peer did not execute the request.
         (define outcome
           (with-handlers ([non-break-failure? (lambda (cause) (uncertain instance cause))])
             (freeze bridge (normalize-outcome (request method (cadr action))))))
         (store-transaction store
           (lambda ()
             (define latest (owned store handle principal))
             (save-state! bridge store latest
               (hash-set* (stored-instance-state latest) 'status "received" 'observed-outcome outcome))))
         (loop)])))
  (define answer #f)
  (let wait ()
    (when (cancelled?) (error 'upstream "request cancelled"))
    (unless (call-with-instance-worker store handle (lambda () (set! answer (execute))))
      (sync (alarm-evt (+ (current-inexact-milliseconds) 25)))
      (wait)))
  answer)
(define (recover-upstream-request! bridge store snapshot handle #:principal principal #:credential-id credential
                                   #:action action #:outcome [outcome #f] #:capabilities [capabilities (hasheq)])
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'upstream "recovery must own its storage transaction boundaries"))
  (unless (memq action '(outcome retry abandon)) (error 'upstream "recovery action must be outcome, retry, or abandon"))
  (define normalized (and (eq? action 'outcome) (freeze bridge (normalize-outcome outcome))))
  (define result #f)
  (unless (call-with-instance-worker store handle
    (lambda ()
      (set! result
        (store-transaction store
          (lambda ()
            (define instance (owned store handle principal))
            (check-binding! bridge snapshot instance credential (stored-instance-arguments instance))
            (define state (stored-instance-state instance))
            (unless (member (hash-ref state 'status) '("in-flight" "received"))
              (error 'upstream "interaction is not awaiting recovery"))
            (record-event! store handle (hasheq 'kind "upstream-recovery" 'action (symbol->string action)))
            (case action
              [(outcome) (local-outcome (stored-instance-state (record-outcome! bridge store instance normalized)) capabilities)]
              [(abandon)
               (define final (hasheq 'error (hasheq 'code -32603 'message "Upstream interaction abandoned")))
               (save-state! bridge store instance (hash-set* state 'status "complete" 'outcome final))
               final]
              [(retry)
               (save-state! bridge store instance (hash-set state 'status "ready"))
               (hasheq 'result (hasheq 'resultType "input_required" 'inputRequests (hasheq)
                 'requestState (continuation-token! store handle (string->symbol (number->string (hash-ref state 'round))))))]))))))
    (error 'upstream "upstream request is active; recovery cannot race its execution"))
  result)
