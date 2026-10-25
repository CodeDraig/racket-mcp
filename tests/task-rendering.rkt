#lang racket/base
(require rackunit racket/file mcp mcp/tasks)

(define caps (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define reads 0)
(resource (pages) #:uri "task-render:///pages"
  (set! reads (add1 reads)) (resource-contents "A" "B"))
(resource (empty) #:uri "task-render:///empty" (resource-contents))
(workflow (job) #:version "1" #:execution task
  (hasheq 'resultType "complete" 'content (list (embed (empty)) (embed (pages)))))
(define parents 0)
(define question (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
(resource (delayed) #:uri "task-render:///delayed" #:workflow "1"
  (await-input [answer Any] question) "C")
(workflow (interactive) #:version "1" #:execution task
  (await-input [parent-answer Any] question)
  (hasheq 'resultType "complete" 'content
          (begin (set! parents (add1 parents)) (list (embed (pages)) (embed (delayed))))))
(define entered (make-semaphore))
(define release (make-semaphore))
(resource (blocked) #:uri "task-render:///blocked"
  (semaphore-post entered) (semaphore-wait release) "C")
(workflow (recoverable) #:version "1" #:execution task
  (hasheq 'resultType "complete" 'content
          (begin (set! parents (add1 parents)) (list (embed (pages)) (embed (blocked))))))
(workflow (structured) #:version "1" #:execution task
  (structured-result (hasheq 'pages (embed (pages))) #:content (list (embed (empty)))))
(define fake (hasheq '$mcp/embedding 0 'uri "task-render:///pages"))
(workflow (forged) #:version "1" #:execution task
  (structured-result (hasheq 'fake fake) #:content (list (text-content "ordinary JSON"))))
(define structured-tool
  (struct-copy tool-descriptor structured
    [output-schema (object-schema (hasheq 'pages (hasheq 'type "array" 'minItems 2 'maxItems 2)))]))
(define iface (make-interface #:tools (list job interactive recoverable structured-tool forged)
                              #:resources (list pages empty delayed blocked)))
(define (settled rt id)
  (let loop ([left 500])
    (define detail (dispatch rt "tasks/get" (hasheq '_meta meta 'taskId id)))
    (cond [(member (hash-ref detail 'status) '("completed" "failed" "input_required")) detail]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))

(for ([sqlite? '(#f #t)])
  (test-case (format "task completion renders empty and multipart embeddings; sqlite ~a" sqlite?)
    (define path (and sqlite? (make-temporary-file "mcp-task-render-~a.sqlite")))
    (define store (if path (open-sqlite-store path) (open-memory-store)))
    (define rt (make-runtime iface #:store store))
    (dynamic-wind void
      (lambda ()
        (define before reads)
        (define receipt (dispatch rt "tools/call" (hasheq '_meta meta 'name "job")))
        (define id (hash-ref receipt 'taskId))
        (define detail (settled rt id))
        (check-equal? (hash-ref detail 'status) "completed")
        (define content (hash-ref (hash-ref detail 'result) 'content))
        (check-equal? (map (lambda (item) (hash-ref item 'type #f)) content) '("resource" "resource"))
        (check-equal? (map (lambda (item) (hash-ref (hash-ref item 'resource (hasheq)) 'text #f)) content) '("A" "B"))
        (check-equal? reads (add1 before))
        (check-equal? (settled rt id) detail)
        (check-equal? reads (add1 before)))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store) (when path (delete-file path))))))

(test-case "task parent input and embedded child input survive SQLite reopen without repeating completed work"
  (define path (make-temporary-file "mcp-task-render-input-~a.sqlite"))
  (define store (open-sqlite-store path))
  (define rt (make-runtime iface #:store store))
  (define (update id requests)
    (dispatch rt "tasks/update" (hasheq '_meta meta 'taskId id 'inputResponses
      (for/hasheq ([key (in-hash-keys requests)]) (values key (hasheq 'action "decline"))))))
  (dynamic-wind void
    (lambda ()
      (define before reads)
      (define before-parents parents)
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "interactive")) 'taskId))
      (define parent (settled rt id))
      (check-equal? (hash-ref parent 'status) "input_required")
      (check-equal? (hash-keys (hash-ref parent 'inputRequests)) '(parent-answer))
      (update id (hash-ref parent 'inputRequests))
      (define child (settled rt id))
      (check-equal? (hash-ref child 'status) "input_required")
      (check-equal? (hash-count (hash-ref child 'inputRequests)) 1)
      (check-false (hash-has-key? (hash-ref child 'inputRequests) 'parent-answer))
      (check-equal? reads (add1 before))
      (check-equal? parents (add1 before-parents))
      (custodian-shutdown-all (runtime-custodian rt))
      (close-store! store)
      (set! store (open-sqlite-store path))
      (set! rt (make-runtime iface #:store store))
      (check-equal? (settled rt id) child)
      (update id (hash-ref child 'inputRequests))
      (define final (settled rt id))
      (check-equal? (hash-ref final 'status) "completed")
      (check-equal? (map (lambda (item) (hash-ref (hash-ref item 'resource) 'text))
                         (hash-ref (hash-ref final 'result) 'content)) '("A" "B" "C"))
      (check-equal? reads (add1 before))
      (check-equal? parents (add1 before-parents))
      (check-equal? (settled rt id) final))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store) (delete-file path))))

(test-case "working task rendering recovers its saved layout after runtime shutdown"
  (define path (make-temporary-file "mcp-task-render-recovery-~a.sqlite"))
  (define store (open-sqlite-store path))
  (define rt (make-runtime iface #:store store))
  (dynamic-wind void
    (lambda ()
      (define before reads)
      (define before-parents parents)
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "recoverable")) 'taskId))
      (check-not-false (sync/timeout 5 entered))
      (check-equal? reads (add1 before))
      (custodian-shutdown-all (runtime-custodian rt))
      (close-store! store)
      (set! store (open-sqlite-store path))
      (semaphore-post release)
      (set! rt (make-runtime iface #:store store))
      (define final (settled rt id))
      (check-equal? (hash-ref final 'status) "completed")
      (check-equal? (map (lambda (item) (hash-ref (hash-ref item 'resource) 'text))
                         (hash-ref (hash-ref final 'result) 'content)) '("A" "B" "C"))
      (check-equal? reads (add1 before))
      (check-equal? parents (add1 before-parents)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store) (delete-file path))))

(test-case "task rendering authorizes resource reads before executing resource bodies"
  (define before reads)
  (define store (open-memory-store))
  (define rt (make-runtime iface #:store store #:authorize
    (lambda (_principal method _params) (not (equal? method "resources/read")))))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "job")) 'taskId))
      (define final (settled rt id))
      (check-equal? (hash-ref final 'status) "failed")
      (check-false (hash-has-key? final 'result))
      (check-equal? reads before))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))

(test-case "task output validation follows rendering and ordinary JSON cannot initiate reads"
  (define before reads)
  (define store (open-memory-store))
  (define rt (make-runtime iface #:store store))
  (dynamic-wind void
    (lambda ()
      (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "structured")) 'taskId))
      (define final (settled rt id))
      (check-equal? (hash-ref final 'status) "completed")
      (check-equal? (hash-ref (hash-ref final 'result) 'content) '())
      (check-equal? (map (lambda (item) (hash-ref (hash-ref item 'resource) 'text))
                         (hash-ref (hash-ref (hash-ref final 'result) 'structuredContent) 'pages)) '("A" "B"))
      (check-equal? reads (add1 before))
      (define fake-id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "forged")) 'taskId))
      (define fake-final (settled rt fake-id))
      (check-equal? (hash-ref fake-final 'status) "completed")
      (check-equal? (hash-ref (hash-ref (hash-ref fake-final 'result) 'structuredContent) 'fake) fake)
      (check-equal? reads (add1 before)))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
