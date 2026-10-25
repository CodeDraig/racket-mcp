#lang racket/base
(require rackunit mcp mcp/tasks (submod mcp/workflow private))
(define payload (vector 'original-raised-value))
(define (settled store id)
  (let loop ([left 500])
    (define task (get-task store id "alice"))
    (cond [(member (hash-ref task 'status) '("completed" "failed")) task]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 5))) (loop (sub1 left))])))
(test-case "a versioned standalone manual effect retains recovery and the replacement schema override"
  (define store (open-memory-store)) (define owner (make-custodian))
  (define calls 0)
  (define adapters (hasheq 'writer (versioned-effect-adapter 'manual
    (lambda args (set! calls (add1 calls)) (raise payload)) "1")))
  (define flow (make-workflow "versioned" "1" "versioned/1"
    (list (workflow-stage 'write 'effect Integer (lambda (_) 41) 'writer 'manual)
          (workflow-stage 'done 'complete Any (lambda (_) (structured-result (hasheq 'n "bad"))) #f #f))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (start-workflow-task flow store (hasheq) "alice" #:adapters adapters #:custodian owner
                            #:output-schema (object-schema (hasheq 'n Integer))) 'taskId))
      (check-equal? (hash-ref (settled store id) 'status) "failed")
      (define original (load-instance store id))
      (define state (stored-instance-state original))
      (define recovery (hash-ref state 'recovery))
      (check-equal? (hash-ref recovery 'workflow) (hash-ref state 'workflow))
      (recover-workflow! store (hash-ref recovery 'workflow) 'write 'outcome #:outcome 42 #:principal "alice")
      (define next (retry-recovered-task! flow store id "alice" #:adapters adapters #:custodian owner #:output-schema #f))
      (check-equal? (hash-ref (settled store (hash-ref next 'taskId)) 'status) "completed")
      (check-false (hash-ref (stored-instance-state (load-instance store (hash-ref next 'taskId))) 'outputSchema))
      (check-equal? (load-instance store id) original) (check-equal? calls 1))
    (lambda () (custodian-shutdown-all owner) (close-store! store))))
(test-case "the first failing child keeps its recovery attribution through an enclosing manual stage"
  (define store (open-memory-store)) (define owner (make-custodian))
  (define inner (make-workflow "inner" "1" "inner/1"
    (list (workflow-stage 'write 'effect Integer (lambda (_) 41) 'inner 'manual)
          (workflow-stage 'done 'complete Any (lambda (_) (text-result "done")) #f #f))))
  (define adapters
    (hasheq 'inner (versioned-effect-adapter 'manual (lambda args (raise payload)) "1")
            'outer (versioned-effect-adapter 'manual
              (lambda args (run-workflow inner store (hasheq) #:principal "alice" #:adapters adapters)) "1")))
  (define outer (make-workflow "outer" "1" "outer/1"
    (list (workflow-stage 'write 'effect Any (lambda (_) 41) 'outer 'manual)
          (workflow-stage 'done 'complete Any (lambda (_) (text-result "done")) #f #f))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (start-workflow-task outer store (hasheq) "alice" #:adapters adapters #:custodian owner) 'taskId))
      (check-equal? (hash-ref (settled store id) 'status) "failed")
      (define state (stored-instance-state (load-instance store id)))
      (define child (load-instance store (hash-ref (hash-ref state 'recovery) 'workflow)))
      (check-equal? (stored-instance-operation child) "inner")
      (check-not-equal? (stored-instance-handle child) (hash-ref state 'workflow)))
    (lambda () (custodian-shutdown-all owner) (close-store! store))))

(test-case "failure observer faults preserve the original raised value"
  (define store (open-memory-store))
  (define flow (make-workflow "original" "1" "original/1"
    (list (workflow-stage 'done 'complete Any (lambda (_) (raise payload)) #f #f))))
  (dynamic-wind void
    (lambda ()
      (parameterize ([current-workflow-failure-observer (lambda args (error 'observer "metadata unavailable"))])
        (check-eq? (with-handlers ([(lambda (_) #t) values]) (run-workflow flow store (hasheq) #:principal "alice")) payload)))
    (lambda () (close-store! store))))
