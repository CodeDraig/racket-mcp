#lang racket/base
(require file/sha1
         "../storage.rkt"
         "../clock.rkt"
         "../json.rkt"
         "../error.rkt"
         (submod "../upstream-bridge.rkt" private)
         "task-time.rkt"
         "task-schema.rkt"
         "elicitation-schema.rkt")
(provide tasks-key check-capabilities! terminal? upstream-task-matches? owned save! detail-fingerprint
         upstream-task-remote-id adopt-upstream-task! local-detail record-detail! fail-uncertain!)
(define tasks-key 'io.modelcontextprotocol/tasks)
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
(define (detail-fingerprint detail)
  (bytes->hex-string (sha256-bytes (open-input-string (json->string (hash-remove detail '_meta))))))
(define (upstream-task-remote-id bridge store snapshot id principal credential source)
  (hash-ref (stored-instance-state (owned bridge store snapshot id principal credential source)) 'remoteId))
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

