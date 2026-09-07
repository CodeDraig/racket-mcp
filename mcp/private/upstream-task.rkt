#lang racket/base
(require racket/list racket/date racket/format "../storage.rkt" "../clock.rkt" "../json.rkt" "../error.rkt"
         "../tasks.rkt" (submod "../upstream-bridge.rkt" private)
         "failure.rkt" "task-schema.rkt" "elicitation-schema.rkt" "input-response.rkt")
(provide adopt-upstream-task! upstream-task-request upstream-task-matches?)
(define tasks-key 'io.modelcontextprotocol/tasks)
(define (timestamp)
  (define d (seconds->date (mcp-current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~aZ" (~r (date-year d) #:min-width 4 #:pad-string "0")
    (~r (date-month d) #:min-width 2 #:pad-string "0") (~r (date-day d) #:min-width 2 #:pad-string "0")
    (~r (date-hour d) #:min-width 2 #:pad-string "0") (~r (date-minute d) #:min-width 2 #:pad-string "0")
    (~r (date-second d) #:min-width 2 #:pad-string "0")))
(define (check-capabilities! capabilities)
  (unless (hash-has-key? (hash-ref capabilities 'extensions (hasheq)) tasks-key)
    (mcp-error -32021 "Client Tasks capability is required"
      (hasheq 'requiredCapabilities (hasheq 'extensions (hasheq tasks-key (hasheq)))))))
(define (terminal? state)
  (and (hash-ref state 'detailed? #f)
       (member (hash-ref (hash-ref state 'task) 'status) '("completed" "failed" "cancelled"))))
(define (upstream-task-matches? instance source)
  (and (equal? (hash-ref (stored-instance-state instance) 'kind #f) "upstream-task")
       (equal? (hash-ref (stored-instance-state instance) 'source #f) source)))
(define (owned bridge store snapshot handle principal credential source)
  (define instance (or (load-instance store handle) (mcp-error -32602 "Unknown upstream task")))
  (unless (and (upstream-task-matches? instance source)
               (equal? principal (stored-instance-principal instance))
               (equal? credential (hash-ref (stored-instance-state instance) 'credential))
               (equal? (stored-instance-fingerprint instance) (fingerprint bridge snapshot))
               (equal? (stored-instance-version instance) "upstream-task/1"))
    (mcp-error -32602 "Unknown, foreign, or incompatible upstream task"))
  (when (<= (stored-instance-expires instance) (mcp-current-seconds)) (mcp-error -32602 "Upstream task expired"))
  instance)
(define (save! bridge store instance state)
  (update-instance! store instance (freeze bridge state)))
(define (adopt-upstream-task! bridge store snapshot parent source capabilities)
  ;; The MRTR bridge calls this inside the transaction returning its recorded
  ;; result. The local task and its immutable creation receipt commit together.
  (check-capabilities! capabilities)
  (define remote (hash-ref (hash-ref (stored-instance-state parent) 'outcome) 'result))
  (unless (task-schema-valid? "CreateTaskResult" remote) (mcp-error -32603 "Malformed upstream task creation"))
  (define remote-ttl (hash-ref remote 'ttlMs))
  (when (and (number? remote-ttl) (<= remote-ttl 0)) (mcp-error -32603 "Upstream task is already expired"))
  (define expiry (min (stored-instance-expires parent)
                      (if (number? remote-ttl) (+ (mcp-current-seconds) (ceiling (/ remote-ttl 1000)))
                          (stored-instance-expires parent))))
  (define candidate
    (create-instance! store (stored-instance-principal parent) "upstream-task"
      (stored-instance-arguments parent) "upstream-task/1" (fingerprint bridge snapshot)
      expiry (hasheq)
      #:key (stored-instance-handle parent)))
  (when (<= (stored-instance-expires candidate) (mcp-current-seconds))
    (mcp-error -32602 "Upstream task expired"))
  (define instance
    (if (hash-has-key? (stored-instance-state candidate) 'creation-result) candidate
        (let* ([id (stored-instance-handle candidate)]
               [task (for/hasheq ([key '(status createdAt lastUpdatedAt pollIntervalMs)]
                                 #:when (hash-has-key? remote key)) (values key (hash-ref remote key)))]
               [local (hash-set* task 'taskId id 'createdAt (timestamp) 'lastUpdatedAt (timestamp)
                                 'ttlMs (* 1000 (- expiry (mcp-current-seconds))))]
               [receipt (hash-set local 'resultType "task")])
          (save! bridge store candidate
            (hasheq 'kind "upstream-task" 'source source 'parent (stored-instance-handle parent)
                    'credential (hash-ref (stored-instance-state parent) 'credential)
                    'remoteId (hash-ref remote 'taskId) 'task local 'creation-result receipt
                    'detailed? #f 'mapping (hasheq) 'accepted (hasheq) 'history (hasheq)
                    'remoteInputs #f 'round 0 'command #f)))))
  (hasheq 'result (hash-ref (stored-instance-state instance) 'creation-result)))
(define (local-detail state capabilities)
  (define task (hash-ref state 'task))
  (when (and (equal? (hash-ref task 'status) "input_required")
             (positive? (hash-count (hash-ref task 'inputRequests)))
             (not (hash-has-key? capabilities 'elicitation)))
    (mcp-error -32021 "Client elicitation capability is required"
      (hasheq 'requiredCapabilities (hasheq 'elicitation (hasheq)))))
  (hash-set task 'resultType "complete"))
(define (record-detail! bridge store instance remote)
  (unless (task-schema-valid? "GetTaskResult" remote) (mcp-error -32603 "Malformed upstream task detail"))
  (define state (stored-instance-state instance))
  (unless (equal? (hash-ref remote 'taskId) (hash-ref state 'remoteId))
    (mcp-error -32603 "Upstream task changed identity"))
  (define inputs (and (equal? (hash-ref remote 'status) "input_required") (hash-ref remote 'inputRequests)))
  (when inputs
    (for ([request (in-hash-values inputs)])
      (unless (and (equal? (hash-ref request 'method #f) "elicitation/create")
                   (elicitation-request-valid? (hash-ref request 'params #f)))
        (mcp-error -32603 "Unsupported upstream task input request"))))
  (define same? (and inputs (equal? inputs (hash-ref state 'remoteInputs))))
  (when (and inputs (not same?) (>= (hash-ref state 'round) (upstream-bridge-max-rounds bridge)))
    (mcp-error -32603 "Upstream task input round limit exceeded"))
  (define mapping
    (if same? (hash-ref state 'mapping)
        (if inputs
            (for/hasheq ([(id request) (in-hash inputs)])
              (values (string->symbol (opaque-handle)) (hasheq 'remote (symbol->string id) 'request request)))
            (hasheq))))
  (define accepted (if same? (hash-ref state 'accepted) (hasheq)))
  (define task
    (hash-set* (for/hasheq ([key '(status statusMessage createdAt lastUpdatedAt pollIntervalMs result error)]
                          #:when (hash-has-key? remote key)) (values key (hash-ref remote key)))
               'taskId (stored-instance-handle instance)
               'createdAt (hash-ref (hash-ref state 'task) 'createdAt)
               'lastUpdatedAt (timestamp)
               'ttlMs (hash-ref (hash-ref state 'task) 'ttlMs)))
  (define detail
    (if inputs (hash-set task 'inputRequests
                 (for/hasheq ([(id entry) (in-hash mapping)] #:unless (hash-has-key? accepted id))
                   (values id (hash-ref entry 'request)))) task))
  (if (equal? remote (hash-ref state 'remoteDetail #f)) instance
  (save! bridge store instance
    (hash-set* state 'task detail 'detailed? #t 'mapping mapping 'accepted accepted
               'remoteInputs inputs 'remoteDetail remote
               'round (if (and inputs (not same?)) (add1 (hash-ref state 'round)) (hash-ref state 'round))))))
(define (fail-uncertain! bridge store instance)
  (define state (stored-instance-state instance))
  (define task (hash-ref state 'task))
  (record-event! store (stored-instance-handle instance) (hasheq 'kind "upstream-task-recovery-required"))
  (save! bridge store instance
    (hash-set* state 'detailed? #t 'task
      (hash-set* (hash-remove task 'inputRequests) 'status "failed" 'lastUpdatedAt (timestamp)
        'error (hasheq 'code -32603 'message "Upstream task mutation is uncertain; explicit recovery is required")))))

(define (upstream-task-request bridge store snapshot request source method id
                               #:principal principal #:credential-id credential
                               #:responses [responses (hasheq)] #:capabilities [capabilities (hasheq)]
                               #:verify [verify void] #:cancelled? [cancelled? (lambda () #f)])
  (check-capabilities! capabilities)
  (unless (member method '("tasks/get" "tasks/update" "tasks/cancel")) (error 'upstream-task "unknown method"))
  (when (eq? (current-store-connection) (state-store-connection store))
    (error 'upstream-task "task requests must own their transaction boundaries"))
  (unless (hash? responses) (mcp-error -32602 "Input responses must be an object"))
  (set! responses (freeze bridge responses))
  (define (latest) (owned bridge store snapshot id principal credential source))
  (void (latest))
  (define answer #f)
  (define changed #f)
  (define (execute)
    (let loop ()
      (when (cancelled?) (error 'upstream-task "request cancelled"))
      (define action
        (store-transaction store
          (lambda ()
            (define instance (latest))
            (define state (stored-instance-state instance))
            (define command (hash-ref state 'command))
            (for ([(key response) (in-hash responses)] #:when (hash-has-key? (hash-ref state 'history) key))
              (unless (equal? response (hash-ref (hash-ref state 'history) key))
                (mcp-error -32602 "Conflicting upstream task input response")))
            (cond
              [(terminal? state)
               (list 'return (if (equal? method "tasks/get") (local-detail state capabilities) (hasheq 'resultType "complete")))]
              [command
               (cond [(equal? (hash-ref command 'status) "intent")
                      (set! changed (fail-uncertain! bridge store instance)) (list 'again)]
                     [else
                      (define task (hash-remove (hash-ref state 'task) 'inputRequests))
                      (set! changed (save! bridge store instance
                        (hash-set* state 'command #f 'lastCommand (hash-ref command 'method)
                          'remoteInputs #f 'remoteDetail #f 'mapping (hasheq) 'accepted (hasheq)
                          'task (hash-set* task 'status "working" 'lastUpdatedAt (timestamp)))))
                      (if (equal? method "tasks/get") (list 'again) (list 'return (hasheq 'resultType "complete")))])]
              [(equal? method "tasks/get") (list 'get (hash-ref state 'remoteId))]
              [(equal? method "tasks/cancel")
               (if (equal? (hash-ref state 'lastCommand #f) "tasks/cancel")
                   (list 'return (hasheq 'resultType "complete"))
                   (list 'send (hasheq 'taskId (hash-ref state 'remoteId))))]
              [else
               (define known (for/hasheq ([(key response) (in-hash responses)]
                                          #:when (hash-has-key? (hash-ref state 'mapping) key)) (values key response)))
               (cond [(zero? (hash-count known)) (list 'return (hasheq 'resultType "complete"))]
                     [else
                      (unless (equal? (hash-ref (hash-ref state 'task) 'status) "input_required")
                        (mcp-error -32602 "Upstream task is not awaiting input"))
                      (define accepted
                        (for/fold ([accepted (hash-ref state 'accepted)]) ([(key response) (in-hash known)])
                          (validate-input-response
                            (hash-ref (hash-ref (hash-ref (hash-ref state 'mapping) key) 'request) 'params) response)
                          (hash-set accepted key response)))
                      (define history
                        (for/fold ([history (hash-ref state 'history)]) ([(key response) (in-hash accepted)])
                          (hash-set history key response)))
                      (define task (hash-ref state 'task))
                      (set! changed (save! bridge store instance
                        (hash-set* state 'accepted accepted 'history history
                          'task (hash-set task 'inputRequests
                            (for/hasheq ([(key value) (in-hash (hash-ref task 'inputRequests))]
                                         #:unless (hash-has-key? accepted key)) (values key value))))))
                      (if (= (hash-count accepted) (hash-count (hash-ref state 'mapping)))
                          (list 'send (hasheq 'taskId (hash-ref state 'remoteId) 'inputResponses
                            (for/hasheq ([(key response) (in-hash accepted)])
                              (values (string->symbol (hash-ref (hash-ref (hash-ref state 'mapping) key) 'remote)) response))))
                          (list 'return (hasheq 'resultType "complete")))])]))))
      (case (car action)
        [(return) (cadr action)]
        [(again) (loop)]
        [(get)
         (verify)
         (define outcome (freeze bridge (request "tasks/get" (hasheq 'taskId (cadr action)))))
         (when (and (not (hash-has-key? outcome 'resultType)) (hash-has-key? outcome 'error)) (mcp-error -32603 "Upstream task polling failed"))
         (define remote (if (hash-has-key? outcome 'resultType) outcome (hash-ref outcome 'result outcome)))
         (define observed
           (store-transaction store
             (lambda ()
               (define prior (latest))
               (define saved (record-detail! bridge store prior remote))
               (unless (= (stored-instance-revision prior) (stored-instance-revision saved)) (set! changed saved))
               saved)))
         (local-detail (stored-instance-state observed) capabilities)]
        [(send)
         (verify)
         (store-transaction store
           (lambda ()
             (when (cancelled?) (error 'upstream-task "request cancelled"))
             (define instance (latest))
             (record-event! store id (hasheq 'kind "upstream-task-intent" 'method method))
             (save! bridge store instance (hash-set (stored-instance-state instance) 'command
               (hasheq 'status "intent" 'method method 'params (cadr action))))))
         (with-handlers ([non-break-failure?
                         (lambda (cause)
                           (store-transaction store (lambda () (set! changed (fail-uncertain! bridge store (latest)))))
                           (mcp-error -32603 "Upstream task mutation requires recovery"))])
           (define outcome (freeze bridge (request method (cadr action))))
           (when (and (not (hash-has-key? outcome 'resultType)) (hash-has-key? outcome 'error)) (error 'upstream-task "upstream mutation failed"))
           (define result (if (hash-has-key? outcome 'resultType) outcome (hash-ref outcome 'result outcome)))
           (unless (task-schema-valid? (if (equal? method "tasks/update") "UpdateTaskResult" "CancelTaskResult") result)
             (error 'upstream-task "malformed mutation response"))
           (store-transaction store
             (lambda ()
               (define instance (latest))
               (define state (stored-instance-state instance))
               (record-event! store id (hasheq 'kind "upstream-task-response" 'method method))
               (save! bridge store instance (hash-set state 'command
                 (hash-set (hash-ref state 'command) 'status "received"))))))
         (loop)])))
  (dynamic-wind void
    (lambda ()
      (let wait ()
        (when (cancelled?) (error 'upstream-task "request cancelled"))
        (unless (call-with-instance-worker store id (lambda () (set! answer (execute))))
          (sync (alarm-evt (+ (current-inexact-milliseconds) 25))) (wait)))
      answer)
    (lambda ()
      (when changed
        (with-handlers ([non-break-failure? (lambda (_) (void))])
          (store-transaction store
            (lambda ()
              (define now (load-instance store id))
              (when (= (stored-instance-revision now) (stored-instance-revision changed))
                ((current-task-notify) principal (hash-ref (stored-instance-state changed) 'task))))))))))
