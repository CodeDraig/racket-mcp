#lang racket/base
(require racket/async-channel racket/list "descriptor.rkt" "error.rkt")
(provide make-subscription-hub listen-subscription publish-change! close-subscriptions!
         current-cancellation-event current-cancelled? current-progress-token progress!)
(struct subscription (id principal filter queue closed overflow?) #:transparent)
(struct hub (lock entries limit) #:transparent)
(define current-cancellation-event (make-parameter never-evt))
(define current-cancelled? (make-parameter (lambda () #f)))
(define current-progress-token (make-parameter #f))
(define (make-subscription-hub #:limit [limit 64]) (hub (make-semaphore 1) (make-hasheq) limit))
(define (tag id params) (hash-set params '_meta (hasheq 'io.modelcontextprotocol/subscriptionId id)))
(define (listen-subscription h id principal filter notify)
  (define key (gensym))
  (define sub (subscription id principal filter (make-async-channel (hub-limit h)) (make-semaphore 0) (box #f)))
  (dynamic-wind
    (lambda ()
      ;; Registration and acknowledgement are ordered under the hub lock.
      (call-with-semaphore (hub-lock h)
        (lambda ()
          (notify (hasheq 'jsonrpc "2.0" 'method "notifications/subscriptions/acknowledged" 'params (tag id (hasheq 'notifications filter))))
          (hash-set! (hub-entries h) key sub))))
    (lambda ()
      (let loop ()
        (define event (sync (wrap-evt (current-cancellation-event) (lambda (_) 'closed))
                            (wrap-evt (semaphore-peek-evt (subscription-closed sub)) (lambda (_) 'closed))
                            (subscription-queue sub)))
        (if (eq? event 'closed) (if (unbox (subscription-overflow? sub)) (mcp-error -32000 "Subscription overflow; re-listen and refresh cached data")
                                  (hasheq 'resultType "complete" '_meta (hasheq 'io.modelcontextprotocol/subscriptionId id)))
            (begin (notify event) (loop)))))
    (lambda () (call-with-semaphore (hub-lock h) (lambda () (hash-remove! (hub-entries h) key))))))
(define (publish-change! h method params #:principal [principal #f])
  (call-with-semaphore (hub-lock h)
    (lambda ()
      (for ([sub (in-hash-values (hub-entries h))])
        (define filter (subscription-filter sub))
        (define matches?
          (and (or (not principal) (equal? principal (subscription-principal sub)))
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
            (set-box! (subscription-overflow? sub) #t) (semaphore-post (subscription-closed sub))))))))
(define (close-subscriptions! h)
  (call-with-semaphore (hub-lock h) (lambda () (for ([sub (in-hash-values (hub-entries h))]) (semaphore-post (subscription-closed sub))))))
(define (progress! token progress #:total [total #f] #:message [message #f])
  (define ctx (or (current-request-context) (error 'progress! "no active request")))
  ((request-context-notify ctx)
   (hasheq 'jsonrpc "2.0" 'method "notifications/progress"
           'params (let* ([p (hasheq 'progressToken token 'progress progress)] [p (if total (hash-set p 'total total) p)]) (if message (hash-set p 'message message) p)))))
