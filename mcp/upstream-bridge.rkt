#lang racket/base
(require "storage.rkt"
         "clock.rkt"
         "error.rkt"
         "private/failure.rkt"
         "private/input-response.rkt"
         "private/upstream-bridge-state.rkt"
         "private/upstream-bridge-recovery.rkt")
(provide make-upstream-bridge upstream-bridge? upstream-bridge-credential-id
         bridge-upstream-request recover-upstream-request!
         (struct-out exn:fail:upstream-recovery))

(module* private #f
  (provide current-upstream-task-result fingerprint freeze check-binding! upstream-bridge-identity upstream-bridge-max-rounds))
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
