#lang racket/base
(require file/sha1
         "../storage.rkt"
         "../json.rkt"
         "../clock.rkt"
         "../error.rkt"
         (submod "../upstream-bridge.rkt" private)
         "upstream-task-state.rkt"
         "upstream-task-request.rkt"
         "task-time.rkt"
         "task-schema.rkt")
(provide recover-upstream-task! retry-upstream-task/core!)
(define (replace-upstream-task! bridge store snapshot id principal credential supplied authorize action)
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'recover-upstream-task! "recovery must own its storage transaction boundaries"))
  (authorize)
  (define received (and (equal? action "outcome") (freeze bridge supplied)))
  (define outcome (if (and (hash? received) (not (hash-has-key? received 'resultType)))
                      (hash-ref received 'result received) received))
  (when (and (equal? action "outcome") (not (task-schema-valid? "GetTaskResult" outcome)))
    (mcp-error -32602 "Repair requires an observed detailed upstream task result"))
  (define digest (bytes->hex-string (sha256-bytes (open-input-string (json->string (if outcome outcome (hasheq 'action "retry")))))))
  (define existing (or (load-instance store id) (mcp-error -32602 "Unknown upstream task")))
  (define source (hash-ref (stored-instance-state existing) 'source #f))
  (void (owned bridge store snapshot id principal credential source))
  (define replacement #f)
  (unless (call-with-instance-worker store id
    (lambda ()
      (set! replacement
        (store-transaction store
          (lambda ()
            (define original (owned bridge store snapshot id principal credential source))
            (define state (stored-instance-state original))
            (unless (or (not outcome) (equal? (hash-ref outcome 'taskId) (hash-ref state 'remoteId)))
              (mcp-error -32602 "Observed outcome belongs to another upstream task"))
            (define prior
              (findf (lambda (event) (equal? (hash-ref event 'kind #f) "upstream-task-replacement"))
                     (instance-events store id)))
            (cond
              [prior
               (unless (equal? (hash-ref prior 'outcomeFingerprint) digest)
                 (mcp-error -32602 "Conflicting upstream task repair outcome"))
               (owned bridge store snapshot (hash-ref prior 'taskId) principal credential source)]
              [else
               (define command (hash-ref state 'command #f))
               (unless (and command (equal? (hash-ref command 'status #f) "intent"))
                 (mcp-error -32602 "Task has no uncertain upstream mutation to repair"))
               ;; A terminated worker may leave its intent before any polling
               ;; request has converted it into the required terminal failure.
               (unless (terminal? state) (set! original (fail-uncertain! bridge store original)))
               (unless (equal? (hash-ref (hash-ref (stored-instance-state original) 'task) 'status) "failed")
                 (mcp-error -32602 "Only a failed uncertain task can be replaced"))
               (define next
                 (create-instance! store principal "upstream-task" (stored-instance-arguments original)
                   (stored-instance-version original) (stored-instance-fingerprint original)
                   (stored-instance-expires original) (hasheq)))
               (define task
                 (hasheq 'taskId (stored-instance-handle next) 'status "working"
                         'createdAt (timestamp) 'lastUpdatedAt (timestamp)
                         'ttlMs (* 1000 (- (stored-instance-expires original) (mcp-current-seconds)))))
               (define seeded
                 (save! bridge store next
                   (hash-set* state 'task task 'detailed? #f 'command #f 'lastCommand #f
                              'mapping (hasheq) 'accepted (hasheq) 'history (hasheq)
                              'remoteInputs #f 'remoteDetail #f 'replacesTask id
                              'repairRetry (and (equal? action "retry") command))))
               (define detailed (if outcome (record-detail! bridge store seeded outcome) seeded))
               (define receipt
                 (hash-set (for/hasheq ([key '(taskId status statusMessage createdAt lastUpdatedAt ttlMs pollIntervalMs)]
                                       #:when (hash-has-key? (hash-ref (stored-instance-state detailed) 'task) key))
                             (values key (hash-ref (hash-ref (stored-instance-state detailed) 'task) key)))
                           'resultType "task"))
               (define saved (save! bridge store detailed (hash-set (stored-instance-state detailed) 'creation-result receipt)))
               (record-event! store id
                 (hasheq 'kind "upstream-task-replacement" 'taskId (stored-instance-handle saved) 'outcomeFingerprint digest 'action action))
               (record-event! store (stored-instance-handle saved)
                 (hasheq 'kind "upstream-task-repair" 'replacesTask id 'outcomeFingerprint digest 'action action))
               saved]))))))
    (error 'recover-upstream-task! "upstream task execution is active; repair cannot race it"))
  replacement)

(define (recover-upstream-task! bridge store snapshot id #:principal principal #:credential-id credential
                                #:outcome supplied #:authorize [authorize void])
  (hash-ref (stored-instance-state
    (replace-upstream-task! bridge store snapshot id principal credential supplied authorize "outcome")) 'creation-result))

(define (retry-upstream-task/core! bridge store snapshot request id principal credential authorize verify)
  (define replacement (replace-upstream-task! bridge store snapshot id principal credential #f authorize "retry"))
  (define state (stored-instance-state replacement))
  (define command (hash-ref state 'repairRetry #f))
  (when command
    (upstream-task-request bridge store snapshot request (hash-ref state 'source) (hash-ref command 'method)
      (stored-instance-handle replacement) #:principal principal #:credential-id credential
      #:capabilities (hasheq 'extensions (hasheq tasks-key (hasheq))) #:verify verify #:retry? #t))
  (hash-ref state 'creation-result))

