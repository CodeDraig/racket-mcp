#lang racket/base
(require racket/async-channel racket/list "descriptor.rkt" "error.rkt" "private/progress.rkt")
(provide subscription-resource-targets make-subscription-hub listen-subscription publish-change! close-subscriptions!
         current-cancellation-event current-cancelled? current-progress-token progress!)
(struct subscription (id principal filter queue closed overflow? owner) #:transparent)
(struct hub (lock entries limit) #:transparent)
(define current-cancellation-event (make-parameter never-evt))
(define current-cancelled? (make-parameter (lambda () #f)))
(define current-progress-token (make-parameter #f))
(define (make-subscription-hub #:limit [limit 64])
  (unless (exact-positive-integer? limit)
    (raise-argument-error 'make-subscription-hub "exact-positive-integer?" limit))
  (hub (make-semaphore 1) (make-hasheq) limit))
;; Forced thread termination need not run dynamic-wind cleanup. Every hub access
;; prunes dead listeners under the lock, including the next registration.
(define (prune-listeners! h)
  (for ([key (in-list (hash-keys (hub-entries h)))]
        #:when (thread-dead? (subscription-owner (hash-ref (hub-entries h) key))))
    (hash-remove! (hub-entries h) key)))
(define (hub-snapshot h)
  (call-with-semaphore (hub-lock h)
    (lambda () (prune-listeners! h) (hash-values (hub-entries h)))))
(define (tag id params) (hash-set params '_meta (hasheq 'io.modelcontextprotocol/subscriptionId id)))
(define (listen-subscription h id principal filter notify)
  (define key (gensym))
  (define sub (subscription id principal filter (make-async-channel (hub-limit h)) (make-semaphore 0) (box #f) (current-thread)))
  (dynamic-wind
    (lambda ()
      (call-with-semaphore (hub-lock h)
        (lambda () (prune-listeners! h) (hash-set! (hub-entries h) key sub))))
    (lambda ()
      ;; Changes can queue during acknowledgement, but only this listener drains
      ;; them, after acknowledgement returns. No transport I/O holds the hub lock.
      (notify (hasheq 'jsonrpc "2.0" 'method "notifications/subscriptions/acknowledged"
                     'params (tag id (hasheq 'notifications filter))))
      (define closed-evt
        (choice-evt (wrap-evt (current-cancellation-event) (lambda (_) 'closed))
                    (wrap-evt (semaphore-peek-evt (subscription-closed sub)) (lambda (_) 'closed))))
      (let loop ()
        (define event (or (sync/timeout 0 closed-evt) (sync closed-evt (subscription-queue sub))))
        (if (or (eq? event 'closed) (sync/timeout 0 closed-evt)) (if (unbox (subscription-overflow? sub)) (mcp-error -32000 "Subscription overflow; re-listen and refresh cached data")
                                  (hasheq 'resultType "complete" '_meta (hasheq 'io.modelcontextprotocol/subscriptionId id)))
            (begin (notify event) (loop)))))
    (lambda () (call-with-semaphore (hub-lock h) (lambda () (hash-remove! (hub-entries h) key))))))
(define (subscription-resource-targets h)
  (append-map (lambda (sub)
                (map (lambda (uri) (cons (subscription-principal sub) uri))
                     (hash-ref (subscription-filter sub) 'resourceSubscriptions '())))
              (hub-snapshot h)))
(define (publish-change! h method params #:principal [principal #f] #:principal-key [principal-key values] #:authorized? [authorized? (lambda (_) #t)])
  (define subscribers (hub-snapshot h))
  (for ([sub (in-list subscribers)])
        (define filter (subscription-filter sub))
        (define matches?
          (and (authorized? (subscription-principal sub)) (or (not principal) (equal? (principal-key principal) (principal-key (subscription-principal sub))))
               (case (string->symbol method)
                 [(notifications/tools/list_changed) (hash-ref filter 'toolsListChanged #f)]
                 [(notifications/prompts/list_changed) (hash-ref filter 'promptsListChanged #f)]
                 [(notifications/resources/list_changed) (hash-ref filter 'resourcesListChanged #f)]
                 [(notifications/resources/updated) (member (hash-ref params 'uri #f) (hash-ref filter 'resourceSubscriptions '()))]
                 [(notifications/tasks) (member (hash-ref params 'taskId #f) (hash-ref filter 'taskIds '()))]
                 [else #f])))
        (when matches?
          (unless (sync/timeout 0 (async-channel-put-evt (subscription-queue sub)
                                                       (hasheq 'jsonrpc "2.0" 'method method 'params (tag (subscription-id sub) params))))
            (set-box! (subscription-overflow? sub) #t) (semaphore-post (subscription-closed sub))))))
(define (close-subscriptions! h)
  (for ([sub (in-list (hub-snapshot h))]) (semaphore-post (subscription-closed sub))))
(define (progress! token progress #:total [total #f] #:message [message #f])
  (unless (current-request-context) (error 'progress! "no active request"))
  (when ((current-cancelled?)) (error 'progress! "request cancelled"))
  (emit-progress!
   (let* ([p (hasheq 'progressToken token 'progress progress)]
          [p (if total (hash-set p 'total total) p)])
     (if message (hash-set p 'message message) p))))
