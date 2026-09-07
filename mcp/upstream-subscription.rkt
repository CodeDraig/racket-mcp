#lang racket/base
(require racket/list racket/async-channel "upstream.rkt" "runtime.rkt" "stdio.rkt" "json.rkt"
         (submod "runtime.rkt" upstream-task-subscriptions))
(provide call-with-upstream-resource-subscription upstream-resource-subscription?
         upstream-resource-subscription-accepted stop-upstream-resource-subscription!
         call-with-upstream-task-subscription upstream-task-subscription?
         upstream-task-subscription-accepted stop-upstream-task-subscription!)
(struct upstream-subscription (ready outcome cancel accepted)
  #:property prop:evt
  (lambda (self)
    (wrap-evt (semaphore-peek-evt (upstream-subscription-ready self))
              (lambda (_) (unbox (upstream-subscription-outcome self))))))
(struct upstream-resource-subscription upstream-subscription ())
(struct upstream-task-subscription upstream-subscription ())
(define upstream-resource-subscription-accepted upstream-subscription-accepted)
(define upstream-task-subscription-accepted upstream-subscription-accepted)
(define (stop-upstream-resource-subscription! subscription)
  ((upstream-subscription-cancel subscription)))
(define stop-upstream-task-subscription! stop-upstream-resource-subscription!)
(define (call-with-upstream-resource-subscription rt source snapshot request uris proc
          #:principal principal #:timeout [timeout 5])
  (unless (runtime? rt) (raise-argument-error 'call-with-upstream-resource-subscription "runtime?" rt))
  (unless (and (procedure? request) (procedure-arity-includes? request 2))
    (raise-argument-error 'call-with-upstream-resource-subscription "request procedure accepting method and parameters" request))
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-upstream-resource-subscription "procedure accepting a subscription" proc))
  (unless (and (list? uris) (pair? uris) (andmap string? uris))
    (raise-argument-error 'call-with-upstream-resource-subscription "nonempty list of resource URI strings" uris))
  (unless (and (rational? timeout) (> timeout 0))
    (raise-argument-error 'call-with-upstream-resource-subscription "positive finite timeout" timeout))
  (define requested (remove-duplicates (map string->immutable-string uris)))
  (define pinned (string->json (json->string snapshot)))
  ;; Resolve every requested URI before contacting the peer. These keys retain
  ;; the installed source identity through local views and principal partitions.
  (define keys (for/hash ([uri (in-list requested)]) (values uri (upstream-resource-change-keys source uri))))
  (call-with-upstream-subscription pinned request requested proc timeout
    'resourceSubscriptions "notifications/resources/updated" 'uri
    (lambda (uri _) (runtime-report-change! rt principal (hash-ref keys uri)))
    upstream-resource-subscription values))

(define (call-with-upstream-task-subscription rt snapshot request ids proc
          #:principal principal #:capabilities capabilities #:timeout [timeout 5])
  (unless (runtime? rt) (raise-argument-error 'call-with-upstream-task-subscription "runtime?" rt))
  (unless (and (list? ids) (pair? ids) (andmap string? ids))
    (raise-argument-error 'call-with-upstream-task-subscription "nonempty list of local task ID strings" ids))
  (unless (and (procedure? request) (procedure-arity-includes? request 2)
               (procedure? proc) (procedure-arity-includes? proc 1))
    (error 'call-with-upstream-task-subscription "expected request and consumer procedures"))
  (unless (and (rational? timeout) (> timeout 0))
    (raise-argument-error 'call-with-upstream-task-subscription "positive finite timeout" timeout))
  (define pinned (string->json (json->string snapshot)))
  (define caps (string->json (json->string capabilities)))
  (define local-ids (remove-duplicates (map string->immutable-string ids)))
  ;; Authorization and persisted snapshot/credential ownership precede all I/O.
  (define mapping
    (for/fold ([mapping (hash)]) ([id (in-list local-ids)])
      (define remote (hash-ref (runtime-upstream-task-target rt id pinned principal caps) 'remoteId))
      (hash-update mapping remote (lambda (prior) (append prior (list id))) '())))
  (call-with-upstream-subscription pinned request (hash-keys mapping) proc timeout
    'taskIds "notifications/tasks" 'taskId
    (lambda (remote detail)
      (for ([id (in-list (hash-ref mapping remote))])
        (runtime-observe-upstream-task! rt id detail #:principal principal #:capabilities caps)))
    upstream-task-subscription
    (lambda (accepted) (filter (lambda (id)
      (for/or ([remote (in-list accepted)]) (member id (hash-ref mapping remote)))) local-ids))))

(define (call-with-upstream-subscription pinned request requested proc timeout
          filter-key change-method change-key forward make-subscription accepted->local)
  (define (send method params)
    (define handle (request method params))
    (unless (request-handle? handle)
      (error 'upstream-subscription "request callback must return a request handle"))
    handle)
  (check-upstream-compatibility! pinned
    (lambda (method params)
      (define handle (send method params))
      (dynamic-wind void
        (lambda ()
          (define value (sync/timeout timeout handle))
          (unless value (error 'upstream-subscription "snapshot request timed out: ~a" method))
          (when (exn? value) (raise value))
          value)
        (lambda () (unless (sync/timeout 0 handle) (request-cancel! handle))))))
  (define peer (send "subscriptions/listen" (hasheq 'notifications (hasheq filter-key requested))))
  (define notices (request-handle-notifications peer))
  (define owner (make-custodian))
  (define stopped (make-semaphore 0))
  (define stopped-evt (semaphore-peek-evt stopped))
  (define cancellation
    (exn:fail:request-cancelled "Upstream subscription cancelled locally"
      (current-continuation-marks) (request-handle-id peer)))
  (define (cancel!)
    ;; Wake the forwarding worker before contacting the borrowed client. Local
    ;; cancellation abandons queued changes; normal completion still drains them.
    (semaphore-post stopped)
    (request-cancel! peer))
  (define worker #f)
  (define subscription #f)
  (define lock (make-semaphore 1))
  (define (finish! value)
    (call-with-semaphore lock
      (lambda ()
        (unless (sync/timeout 0 (semaphore-peek-evt (upstream-subscription-ready subscription)))
          (set-box! (upstream-subscription-outcome subscription) value)
          (semaphore-post (upstream-subscription-ready subscription))))))
  (define (tagged-params message)
    (unless (hash? message) (error 'upstream-subscription "expected a notification object"))
    (define params (hash-ref message 'params #f))
    (unless (and (hash? params) (hash? (hash-ref params '_meta #f))
                 (equal? (hash-ref (hash-ref params '_meta) 'io.modelcontextprotocol/subscriptionId #f)
                         (request-handle-id peer)))
      (error 'upstream-subscription "notification has an incorrect subscription ID"))
    params)
  (define events
    (choice-evt (wrap-evt notices (lambda (notice) (cons 'notice notice)))
                (wrap-evt peer (lambda (outcome) (cons 'outcome outcome)))
                (wrap-evt stopped-evt (lambda (_) (cons 'stopped #f)))))
  (define (next-event wait)
    (define queued (sync/timeout 0 notices))
    (define event (if queued (cons 'notice queued) (sync/timeout wait events)))
    ;; Completion may become ready between the first queue check and sync.
    (cond [(sync/timeout 0 stopped-evt) (cons 'stopped #f)]
          [(and event (eq? (car event) 'outcome))
        (let ([last-notice (sync/timeout 0 notices)])
          (if last-notice (cons 'notice last-notice) event))]
          [else event]))
  (define (terminal outcome)
    (cond [(exn? outcome) outcome]
          [(and (hash? outcome) (hash-has-key? outcome 'error)) outcome]
          [else
           (define result (and (hash? outcome) (hash-ref outcome 'result #f)))
           (unless (and (hash? result) (equal? (hash-ref result 'resultType #f) "complete")
                        (hash? (hash-ref result '_meta #f))
                        (equal? (hash-ref (hash-ref result '_meta) 'io.modelcontextprotocol/subscriptionId #f)
                                (request-handle-id peer)))
             (error 'upstream-subscription "invalid subscription completion result"))
           outcome]))
  (dynamic-wind void
    (lambda ()
      (define first (next-event timeout))
      (unless first (error 'upstream-subscription "acknowledgement timed out"))
      (when (eq? (car first) 'outcome)
        (if (exn? (cdr first)) (raise (cdr first))
            (error 'upstream-subscription "subscription completed before acknowledgement: ~s" (cdr first))))
      (define params (tagged-params (cdr first)))
      (unless (equal? (hash-ref (cdr first) 'method #f) "notifications/subscriptions/acknowledged")
        (error 'upstream-subscription "expected acknowledgement before changes"))
      (define accepted (hash-ref params 'notifications #f))
      (unless (and (hash? accepted)
                   (andmap (lambda (key) (eq? key filter-key)) (hash-keys accepted))
                   (list? (hash-ref accepted filter-key '()))
                   (andmap (lambda (uri) (and (string? uri) (member uri requested)))
                           (hash-ref accepted filter-key '())))
        (error 'upstream-subscription "acknowledgement contains an unrequested filter"))
      (define accepted-ids (remove-duplicates (map string->immutable-string (hash-ref accepted filter-key '()))))
      (set! subscription
        (make-subscription (make-semaphore 0) (box #f)
          cancel! (accepted->local accepted-ids)))
      (set! worker
        (parameterize ([current-custodian owner])
          (thread
            (lambda ()
              (with-handlers ([(lambda (_) #t)
                               (lambda (failure)
                                 (finish! (if (exn? failure) failure
                                              (exn:fail (format "Upstream forwarding raised: ~s" failure) (current-continuation-marks))))
                                 (cancel!))])
                (let loop ()
                  ;; Drain already queued notices before observing stream completion.
                  (define event (next-event #f))
                  (cond
                    [(eq? (car event) 'stopped) (finish! cancellation)]
                    [(eq? (car event) 'outcome) (finish! (terminal (cdr event)))]
                    [else
                     (define notice (cdr event))
                     (define values (tagged-params notice))
                     (define id (hash-ref values change-key #f))
                     (unless (and (equal? (hash-ref notice 'method #f) change-method)
                                  (member id accepted-ids))
                       (error 'upstream-subscription "received an unaccepted ~a change"
                              (if (eq? filter-key 'taskIds) "task" "resource")))
                     (forward id values)
                     (loop)])))))))
      (proc subscription))
    (lambda ()
      (parameterize-break #f
        (with-handlers ([(lambda (_) #t) void]) (cancel!))
        (when worker (sync/timeout timeout worker))
        (custodian-shutdown-all owner)
        (when subscription
          (finish! cancellation))))))
