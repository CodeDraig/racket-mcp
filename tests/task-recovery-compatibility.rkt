#lang racket/base
(require rackunit racket/file racket/list mcp mcp/tasks)
(define caps (hasheq 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq))))
(define meta (request-meta #:capabilities caps))
(define (settled store id)
  (let loop ([left 500])
    (define task (get-task store id "alice"))
    (cond [(member (hash-ref task 'status) '("failed" "completed" "input_required")) task]
          [(zero? left) (error 'test "task did not settle")]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
(define (revisions store)
  (sort (for/list ([instance (in-list (list-instances store))])
          (list (stored-instance-handle instance) (stored-instance-revision instance))) string<? #:key car))
(define (journals store)
  (for/hash ([instance (in-list (list-instances store))])
    (values (stored-instance-handle instance) (instance-events store (stored-instance-handle instance)))))

(for* ([sqlite? '(#f #t)] [nested? '(#f #t)] [change '(version fingerprint renderer adapter ancestor-renderer)]
       #:when (or nested? (not (eq? change 'ancestor-renderer))))
  (test-case (format "child ~a checked before allocation, nested ~s, sqlite ~s" change nested? sqlite?)
    (define directory (and sqlite? (make-temporary-file "recovery-compatibility-~a" 'directory)))
    (define path (and directory (build-path directory "state.sqlite")))
    (define store (if path (open-sqlite-store path) (open-memory-store)))
    (define parents 0)
    (define leading-reads 0)
    (define calls 0)
    (define wrappers 0)
    (define renders 0)
    (define renderer (make-text-renderer "child" "1" (lambda (value) (set! renders (add1 renders)) value)))
    (define child-flow (make-workflow "child" "1" "child/1"
      (list (workflow-stage 'effect 'effect Integer (lambda (_) 41) 'writer 'manual)
            (workflow-stage 'done 'complete Any (lambda (env) (number->string (hash-ref env 'effect))) #f #f))))
    (define child (make-resource "child" "repair:///child" void #:workflow child-flow #:render renderer))
    (define wrapper (make-resource "wrapper" "repair:///wrapper" void #:workflow
      (make-workflow "wrapper" "1" "wrapper/1"
        (list (workflow-stage 'done 'complete Any
          (lambda (_) (set! wrappers (add1 wrappers)) (text-presentation (embed (child)))) #f #f)))))
    ;; A second mount of the same executable must not make recovery ambiguous.
    (define alias (make-resource "alias" "repair:///alias" void #:workflow child-flow))
    (define leading (make-resource "leading" "repair:///leading" (lambda () (set! leading-reads (add1 leading-reads)) "first")))
    (define parent (make-workflow "parent" "1" "parent/1"
      (list (workflow-stage 'done 'complete Any
        (lambda (_) (set! parents (add1 parents))
          (hasheq 'resultType "complete" 'content
            (list (embed (leading)) (embed (if nested? (wrapper) (child)))))) #f #f))))
    (define tool (make-tool "parent" '() void #:workflow parent #:execution 'task))
    (define adapters (hasheq 'writer (effect-adapter 'manual
      (lambda args (set! calls (add1 calls)) (error 'writer "uncertain")))))
    (define runtimes '())
    (define (make-rt resource [ancestor wrapper] [adapter-version "1"])
      (define iface (mount-interfaces
        (make-interface #:tools (list tool) #:resources (list leading ancestor alias))
        (view (make-interface #:resources (list resource)) #:adapters
          (hasheq 'writer (versioned-effect-adapter 'manual (effect-adapter-invoke (hash-ref adapters 'writer)) adapter-version)))))
      (define rt (make-runtime iface #:store store #:adapters adapters))
      (set! runtimes (cons rt runtimes)) rt)
    (define rt (make-rt child))
    (dynamic-wind void
      (lambda ()
        (define id (hash-ref (dispatch rt "tools/call" (hasheq '_meta meta 'name "parent") #:principal "alice") 'taskId))
        (define failed (settled store id))
        (check-equal? (hash-ref failed 'status) "failed")
        (define state (stored-instance-state (load-instance store id)))
        (define child-id (hash-ref (hash-ref state 'recovery) 'workflow))
        (recover-workflow! store child-id 'effect 'outcome #:outcome 42 #:principal "alice")
        (when path
          (custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
          (set! store (open-sqlite-store path)) (set! rt (make-rt child)))
        (define incompatible
          (case change
            [(version) (struct-copy resource-descriptor child [workflow (struct-copy workflow-descriptor child-flow [version "2"])])]
            [(fingerprint) (struct-copy resource-descriptor child [workflow (struct-copy workflow-descriptor child-flow [fingerprint "child/2"])])]
            [(renderer) (struct-copy resource-descriptor child [renderer (struct-copy resource-renderer renderer [version "2"])])]
            [else child]))
        (define ancestor
          (if (eq? change 'ancestor-renderer)
              (struct-copy resource-descriptor wrapper [renderer (make-text-renderer "wrapper" "2" values)]) wrapper))
        (define changed (make-rt incompatible ancestor (if (eq? change 'adapter) "2" "1")))
        (define before (revisions store))
        (define events (journals store))
        (define rejected (with-handlers ([exn:fail? values])
          (retry-runtime-task! changed id #:principal "alice" #:capabilities caps)))
        ;; Wait for the baseline's incorrectly allocated worker before comparing.
        (when (hash? rejected) (void (settled store (hash-ref rejected 'taskId))))
        (check-true (exn:fail? rejected))
        (check-equal? (revisions store) before)
        (check-equal? (journals store) events)
        (check-equal? renders 0)
        (check-equal? wrappers (if nested? 1 0))
        (define next (retry-runtime-task! rt id #:principal "alice" #:capabilities caps))
        (define final (settled store (hash-ref next 'taskId)))
        (check-equal? (hash-ref final 'status) "completed")
        (check-equal? (map (lambda (item) (hash-ref (hash-ref item 'resource) 'text))
                           (hash-ref (hash-ref final 'result) 'content)) '("first" "42"))
        (check-equal? (get-task store id "alice") failed)
        (when path
          (for ([runtime (in-list runtimes)]) (custodian-shutdown-all (runtime-custodian runtime)))
          (close-store! store) (set! store (open-sqlite-store path)) (set! rt (make-rt child)))
        (check-equal? (hash-ref (retry-runtime-task! rt id #:principal "alice" #:capabilities caps) 'taskId)
                      (hash-ref next 'taskId))
        (check-equal? parents 1) (check-equal? leading-reads 1) (check-equal? calls 1)
        (check-equal? wrappers (if nested? 1 0)) (check-equal? renders 1))
      (lambda ()
        (for ([runtime (in-list runtimes)]) (custodian-shutdown-all (runtime-custodian runtime)))
        (close-store! store) (when directory (delete-directory/files directory))))))
