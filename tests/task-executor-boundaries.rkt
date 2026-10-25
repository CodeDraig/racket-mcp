#lang racket/base
(require rackunit mcp mcp/tasks)

(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define (settled store id)
  (let loop ([left 500])
    (define detail (get-task store id "alice"))
    (cond [(member (hash-ref detail 'status) '("completed" "failed" "input_required")) detail]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))

(test-case "task workers resume bound defaults without revalidating them as wire input"
  (define defaults 0)
  (workflow (job [n Integer #:default (begin (set! defaults (add1 defaults)) 7)])
    #:version "1" #:execution task-optional
    (structured-result n))
  (define tool (struct-copy tool-descriptor job [input-schema (hasheq 'type "object" 'maxProperties 0)]))
  (define store (open-memory-store))
  (define rt (make-runtime (make-interface #:tools (list tool)) #:store store))
  (dynamic-wind void
    (lambda ()
      (define (call params capabilities)
        (dispatch rt "tools/call" (hash-set params '_meta (request-meta #:capabilities capabilities)) #:principal "alice"))
      (define plain (call (hasheq 'name "job") (hasheq)))
      (check-equal? (hash-ref plain 'structuredContent) 7)
      (check-equal? defaults 1)
      (define receipt (call (hasheq 'name "job") caps))
      (define id (hash-ref receipt 'taskId))
      (define final (settled store id))
      (check-equal? (hash-ref final 'status) "completed")
      (check-equal? (hash-ref final 'result) plain)
      (check-equal? defaults 2)
      (define records (list-instances store))
      (check-exn exn:fail:mcp? (lambda () (call (hasheq 'name "job" 'arguments (hasheq 'n 7)) caps)))
      (check-equal? (list-instances store) records)
      (check-equal? defaults 2))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))

(for ([context '(standalone handler worker)])
  (test-case (format "low-level unpublished workflow retains its supplied executor in ~a" context)
    (define calls 0)
    (define flow (make-workflow "private-job" "1" "private-job/1"
      (list (workflow-stage 'value 'effect Integer (lambda (_) 41) 'provided 'idempotent)
            (workflow-stage 'done 'complete Any (lambda (env) (text-result (number->string (hash-ref env 'value)))) #f #f))))
    (define adapters (hasheq 'provided (effect-adapter 'idempotent
      (lambda (value _key _connection) (set! calls (add1 calls)) (add1 value)))))
    (define store (open-memory-store))
    (define rt #f)
    (define (start)
      (start-workflow-task flow store (hasheq) "alice" #:adapters adapters
        #:output-schema #f #:custodian (runtime-custodian rt)))
    (define launch (make-tool "launch" '() (lambda (_) (structured-result (start)))))
    (workflow (parent) #:version "1" #:execution task
      (structured-result (start)))
    (set! rt (make-runtime (make-interface #:tools (list launch parent)) #:store store))
    (dynamic-wind void
      (lambda ()
        (define receipt
          (case context
            [(standalone) (start)]
            [(handler)
             (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "launch") #:principal "alice") 'structuredContent)]
            [(worker)
             (define parent-receipt (dispatch rt "tools/call" (hasheq '_meta meta 'name "parent") #:principal "alice"))
             (define parent-final (settled store (hash-ref parent-receipt 'taskId)))
             (check-equal? (hash-ref parent-final 'status) "completed")
             (hash-ref (hash-ref parent-final 'result) 'structuredContent)]))
        (define final (settled store (hash-ref receipt 'taskId)))
        (check-equal? (hash-ref final 'status) "completed")
        (check-equal? (hash-ref final 'result) (text-result "42"))
        (check-equal? calls 1))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)))))
