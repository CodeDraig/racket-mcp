#lang racket/base
(require rackunit mcp (submod mcp/workflow private) mcp/upstream)
(define form (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define completions 0)
(define (factory)
  (make-workflow "work" "1" "program/1"
    (list (workflow-stage 'answer 'input Any (lambda (_) form) #f #f)
          (workflow-stage 'done 'complete Any (lambda (_) (set! completions (add1 completions)) (text-result "done")) #f #f))))
(test-case "declared identities survive factories and copying, without claiming capture"
  (define identity (string-copy "application/1"))
  (define flow (call-with-build-identity identity factory))
  (string-set! identity 0 #\X)
  (define fingerprint (workflow-executable-fingerprint flow (hash)))
  (check-equal? (hash-ref (string->json fingerprint) 'identity) "application/1")
  (check-equal? (hash-ref (string->json (workflow-executable-fingerprint
    (workflow-add-fingerprint-suffix flow ":renderer") (hash))) 'identity) "application/1")
  (check-equal? (call-with-build-identity "application/1" (lambda () (workflow-executable-fingerprint flow (hash)))) fingerprint)
  (check-exn #rx"conflicting build identities"
    (lambda () (call-with-build-identity "application/2" (lambda () (workflow-executable-fingerprint flow (hash))))))
  (check-exn exn:fail:contract? (lambda () (call-with-build-identity "" factory)))
  (check-exn exn:fail:contract? (lambda () (make-runtime (make-interface) #:build-id 42)))
  (define store (open-memory-store))
  (dynamic-wind void
    (lambda ()
      (define pending (run-workflow flow store (hasheq) #:principal "alice"))
      (define changed (call-with-build-identity "application/2" factory))
      (check-exn exn:fail:recovery? (lambda () (run-workflow changed store (hasheq) #:principal "alice" #:state (hash-ref pending 'requestState))))
      (check-equal? completions 0)
      (check-equal? (hash-ref (run-workflow flow store (hasheq) #:principal "alice"
        #:state (hash-ref pending 'requestState) #:responses (hasheq 'answer (hasheq 'action "decline"))) 'resultType) "complete"))
    (lambda () (close-store! store))))

(define (macro-factory)
  (workflow (generated) #:version "1"
    (await-input [answer Any] form)
    (text-result "macro"))
  generated)
(resource (child) #:uri "test:///child" #:workflow "1"
  (await-input [answer Any] form)
  "child")
(tool (parent) (structured-result (hasheq) #:content (list (embed (child)))))
(define (call rt method params)
  (dispatch rt method (hash-set params '_meta (request-meta #:capabilities caps)) #:principal "alice"))
(test-case "runtime identity guards macro workflow and plain parent rendering"
  (define store (open-memory-store))
  (define iface (make-interface #:tools (list (macro-factory) parent) #:resources (list child)))
  (define id (string-copy "runtime/1"))
  (define one (make-runtime iface #:store store #:build-id id))
  (string-set! id 0 #\X)
  (define two (make-runtime iface #:store store #:build-id "runtime/2"))
  (dynamic-wind void
    (lambda ()
      (check-equal? (runtime-build-identity one) "runtime/1")
      (for ([name '("generated" "parent")])
        (define pending (call one "tools/call" (hasheq 'name name)))
        (define resume (hasheq 'name name 'requestState (hash-ref pending 'requestState)
          'inputResponses (for/hasheq ([key (in-hash-keys (hash-ref pending 'inputRequests))])
                            (values key (hasheq 'action "decline")))))
        (check-exn exn:fail? (lambda () (call two "tools/call" resume)))
        (check-equal? (hash-ref (call one "tools/call" resume) 'resultType) "complete")))
    (lambda () (for-each (lambda (rt) (custodian-shutdown-all (runtime-custodian rt))) (list one two)) (close-store! store))))

(test-case "macro construction scope retains identity outside that scope"
  (define generated (call-with-build-identity "owned/1" macro-factory))
  (check-equal? (hash-ref (string->json (workflow-executable-fingerprint (tool-descriptor-workflow generated) (hash))) 'identity) "owned/1")
  (define rt (make-runtime (make-interface #:tools (list generated)) #:store (open-memory-store) #:build-id "other/2"))
  (dynamic-wind void
    (lambda () (check-exn #rx"conflicting build identities" (lambda () (call rt "tools/call" (hasheq 'name "generated")))))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! (runtime-store rt)))))

(test-case "upstream continuation and task bindings include runtime identity"
  (define snapshot
    (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities (hasheq 'tools (hasheq) 'extensions (hash-ref caps 'extensions)))
      'tools/list (hasheq 'tools (list (hasheq 'name "remote" 'inputSchema (hasheq 'type "object"))))
      'resources/list (hasheq 'resources '()) 'resources/templates/list (hasheq 'resourceTemplates '()) 'prompts/list (hasheq 'prompts '())))
  (for ([task? '(#f #t)])
    (define sent 0)
    (define (peer method params)
      (or (hash-ref snapshot (string->symbol method) #f)
        (begin (set! sent (add1 sent))
          (if task?
            (hasheq 'resultType "task" 'taskId "remote-task" 'status "working" 'createdAt "2026-09-08T00:00:00Z" 'lastUpdatedAt "2026-09-08T00:00:00Z" 'ttlMs 60000)
            (if (hash-has-key? params 'requestState) (text-result "remote-done")
              (hasheq 'resultType "input_required" 'requestState "remote-state"
                'inputRequests (hasheq 'answer (hasheq 'method "elicitation/create" 'params form))))))))
    (define store (open-memory-store))
    (define iface (make-upstream-interface snapshot peer #:bridge
      (make-upstream-bridge #:identity "peer" #:version "1" #:credential-id (lambda (_) "account"))))
    (define one (make-runtime iface #:store store #:build-id "upstream/1"))
    (define two (make-runtime iface #:store store #:build-id "upstream/2"))
    (dynamic-wind void
      (lambda ()
        (define pending (call one "tools/call" (hasheq 'name "remote")))
        (define params (if task? (hasheq 'taskId (hash-ref pending 'taskId))
          (hasheq 'name "remote" 'requestState (hash-ref pending 'requestState))))
        (check-exn exn:fail? (lambda () (call two (if task? "tasks/get" "tools/call") params)))
        (check-equal? sent 1)
        (unless task?
          (check-equal? (hash-ref (call one "tools/call" (hash-set params 'inputResponses
            (for/hasheq ([key (in-hash-keys (hash-ref pending 'inputRequests))]) (values key (hasheq 'action "decline"))))) 'resultType) "complete")))
      (lambda () (for-each (lambda (rt) (custodian-shutdown-all (runtime-custodian rt))) (list one two)) (close-store! store)))))

(workflow (background) #:version "1" #:execution task
  (await-input [answer Any] form)
  (text-result "background-done"))
(test-case "task input rejects changed build before persistence"
  (define store (open-memory-store))
  (define iface (make-interface #:tools (list background)))
  (define one (make-runtime iface #:store store #:build-id "tasks/1"))
  (define two (make-runtime iface #:store store #:build-id "tasks/2"))
  (dynamic-wind void
    (lambda ()
      (define receipt (call one "tools/call" (hasheq 'name "background")))
      (define id (hash-ref receipt 'taskId))
      (define params (hasheq 'taskId id))
      (define (await-status status)
        (let loop ([left 100])
          (define result (call one "tasks/get" params))
          (cond [(equal? (hash-ref result 'status) status) result]
                [(zero? left) (error 'test "task status did not reach ~a: ~s" status result)]
                [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
      (define pending (await-status "input_required"))
      (define revision (stored-instance-revision (load-instance store id)))
      (define update (hash-set params 'inputResponses (hasheq 'answer (hasheq 'action "decline"))))
      (check-exn #rx"build is incompatible" (lambda () (call two "tasks/update" update)))
      (check-equal? (stored-instance-revision (load-instance store id)) revision)
      (check-equal? (call one "tasks/get" params) pending)
      (void (call one "tasks/update" update))
      (define done (await-status "completed"))
      (void (call two "tasks/cancel" params))
      (check-equal? (call two "tasks/get" params) done))
    (lambda () (for-each (lambda (rt) (custodian-shutdown-all (runtime-custodian rt))) (list one two)) (close-store! store))))

(test-case "startup task recovery uses the runtime declaration"
  (for ([changed? '(#f #t)])
    (define store (open-memory-store))
    (define iface (make-interface #:tools (list background)))
    (define one (make-runtime iface #:store store #:build-id "recovery/1"))
    (define two #f)
    (dynamic-wind void
      (lambda ()
        (define id (hash-ref (call one "tools/call" (hasheq 'name "background")) 'taskId))
        (define (await-status rt expected)
          (let loop ([left 100])
            (define result (call rt "tasks/get" (hasheq 'taskId id)))
            (cond [(equal? (hash-ref result 'status) expected) result]
                  [(zero? left) (error 'test "unexpected recovery status: ~s" result)]
                  [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
        (void (await-status one "input_required"))
        (custodian-shutdown-all (runtime-custodian one))
        ;; The persisted boundary after accepting input, before its worker runs.
        (define instance (load-instance store id))
        (define state (stored-instance-state instance))
        (void (update-instance! store instance
          (hash-set* state 'responses (hasheq 'answer (hasheq 'action "decline"))
            'task (hash-set (hash-remove (hash-ref state 'task) 'inputRequests) 'status "working"))))
        (set! two (make-runtime iface #:store store #:build-id (if changed? "recovery/2" "recovery/1")))
        (define result (await-status two (if changed? "failed" "completed")))
        (if changed?
          (check-equal? (hash-ref (hash-ref result 'error) 'code) -32603)
          (check-equal? (hash-ref (car (hash-ref (hash-ref result 'result) 'content)) 'text) "background-done")))
      (lambda () (custodian-shutdown-all (runtime-custodian one))
        (when two (custodian-shutdown-all (runtime-custodian two))) (close-store! store)))))
