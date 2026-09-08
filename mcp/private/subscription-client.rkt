#lang racket/base
(require "../json.rkt")
(provide make-subscription-tracker observe-subscription! subscription-notification-id check-subscription-result!)

;; Each tracker belongs to a single request reader (or the stdio client lock).
(struct subscription-tracker (id requested accepted) #:mutable)
(define (make-subscription-tracker id method params)
  (and (equal? method "subscriptions/listen")
       (subscription-tracker id (string->json (json->string (hash-ref params 'notifications (hasheq)))) #f)))
(define (subscription-notification-id method params)
  (define id (hash-ref (hash-ref params '_meta (hasheq)) 'io.modelcontextprotocol/subscriptionId missing))
  (when (or (not (missing? id))
            (member method '("notifications/subscriptions/acknowledged"
                             "notifications/tools/list_changed" "notifications/prompts/list_changed"
                             "notifications/resources/list_changed" "notifications/resources/updated"
                             "notifications/tasks")))
    (unless (or (string? id) (exact-integer? id))
      (error 'subscription "Missing or invalid subscription ID")))
  id)
(define list-fields '(toolsListChanged promptsListChanged resourcesListChanged))
(define member-fields '(resourceSubscriptions taskIds))
(define (accepted-subset? accepted requested)
  (and (hash? accepted) (hash? requested)
       (for/and ([(key value) (in-hash accepted)])
         (define want (hash-ref requested key missing))
         (cond
           [(memq key list-fields)
            (and (boolean? value) (or (not value) (eq? want #t)))]
           [(memq key member-fields)
            (and (list? value) (andmap string? value)
                 (or (null? value)
                     (and (list? want) (for/and ([item (in-list value)]) (member item want)))))]
           ;; Extension filters have no generic subset algebra. Preserve exact
           ;; accepted values; do not guess the semantics of unknown fields.
           [else (and (not (missing? want)) (equal? want value))]))))
(define (observe-subscription! tracker method params)
  (define id (hash-ref (hash-ref params '_meta (hasheq)) 'io.modelcontextprotocol/subscriptionId missing))
  (unless (and tracker (equal? id (subscription-tracker-id tracker)))
    (error 'subscription "Unrelated subscription notification"))
  (define accepted (subscription-tracker-accepted tracker))
  (cond
    [(equal? method "notifications/subscriptions/acknowledged")
     (when accepted (error 'subscription "Duplicate subscription acknowledgement"))
     (define filter (hash-ref params 'notifications missing))
     (unless (accepted-subset? filter (subscription-tracker-requested tracker))
       (error 'subscription "Acknowledged filter is not a valid subset of the requested filter"))
     (set-subscription-tracker-accepted! tracker (string->json (json->string filter)))]
    [else
     (unless accepted (error 'subscription "Notification precedes subscription acknowledgement"))
     (define allowed?
       (cond
         [(equal? method "notifications/tools/list_changed") (eq? (hash-ref accepted 'toolsListChanged #f) #t)]
         [(equal? method "notifications/prompts/list_changed") (eq? (hash-ref accepted 'promptsListChanged #f) #t)]
         [(equal? method "notifications/resources/list_changed") (eq? (hash-ref accepted 'resourcesListChanged #f) #t)]
         [(equal? method "notifications/resources/updated")
          (member (hash-ref params 'uri missing) (hash-ref accepted 'resourceSubscriptions '()))]
         [(equal? method "notifications/tasks")
          (member (hash-ref params 'taskId missing) (hash-ref accepted 'taskIds '()))]
         [else #t]))
     (unless allowed? (error 'subscription "Notification is outside the acknowledged subscription filter"))]))

;; Establishment failures need no acknowledgement. Successful completion closes
;; an established stream and must carry its identity, just like its events.
(define (check-subscription-result! tracker message)
  (when (and tracker (hash-has-key? message 'result))
    (define result (hash-ref message 'result))
    (unless (and (equal? (hash-ref result 'resultType "complete") "complete")
                 (equal? (hash-ref (hash-ref result '_meta (hasheq))
                                   'io.modelcontextprotocol/subscriptionId missing)
                         (subscription-tracker-id tracker)))
      (error 'subscription "Invalid subscription completion result or subscription ID"))
    (unless (subscription-tracker-accepted tracker)
      (error 'subscription "Completion precedes subscription acknowledgement"))))
