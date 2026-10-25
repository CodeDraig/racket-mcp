#lang racket/base
(require rackunit racket/file mcp)
(define seen '())
(define (adapter label version)
  (versioned-effect-adapter 'idempotent
    (lambda (input key tx) (set! seen (cons label seen)) (string-append label input)) version))
(define a (adapter "A" "a/1"))
(define b (adapter "B" "b/1"))
(define question (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
(workflow (write [value String]) #:version "1"
  (await-input [answer Any] question)
  (perform [result String] #:adapter writer #:policy idempotent value)
  (text-result result))
(resource (report [value String]) #:uri "report:///{value}" #:workflow "1"
  (perform [result String] #:adapter writer #:policy idempotent value)
  result)
(prompt (review [value String]) #:workflow "1"
  (perform [result String] #:adapter writer #:policy idempotent value)
  (role "user" (text-content result)))
(define base (make-interface #:tools (list write) #:resources (list report) #:prompts (list review)))
(define (mounted first)
  (mount-interfaces (view base #:namespace "a/" #:uris (hash "report:///{value}" "a:///{value}") #:adapters (hasheq 'writer first))
                    (view base #:namespace "b/" #:uris (hash "report:///{value}" "b:///{value}") #:adapters (hasheq 'writer b))))
(define path (make-temporary-file "mcp-view-adapters-~a.sqlite"))
(define store (open-sqlite-store path))
(define rt (make-runtime (mounted a) #:store store #:adapters (hasheq 'writer (adapter "Wrong" "global/1"))))
(define (call runtime method params)
  (dispatch runtime method (hash-set params '_meta (request-meta #:capabilities
    (hasheq 'elicitation (hasheq) 'extensions (hasheq 'io.modelcontextprotocol/tasks (hasheq)))))))
(define pending (call rt "tools/call" (hasheq 'name "a/write" 'arguments (hasheq 'value "x"))))
(check-equal? seen '())
(define retry (hasheq 'name "a/write" 'arguments (hasheq 'value "x") 'requestState (hash-ref pending 'requestState)
  'inputResponses (hasheq 'answer (hasheq 'action "decline"))))
(custodian-shutdown-all (runtime-custodian rt)) (close-store! store)
(set! store (open-sqlite-store path))
(define changed (make-runtime (mounted (adapter "Changed" "a/2")) #:store store))
(check-exn exn:fail:recovery? (lambda () (call changed "tools/call" retry)))
(check-equal? seen '())
(set! rt (make-runtime (mounted (adapter "A" "a/1")) #:store store))
(check-equal? (hash-ref (call rt "tools/call" retry) 'content) (list (text-content "Ax")))
(check-equal? (call rt "tools/call" retry) (text-result "Ax"))
(check-equal? seen '("A"))
(check-equal? (hash-ref (car (hash-ref (call rt "resources/read" (hasheq 'uri "b:///x")) 'contents)) 'text) "Bx")
(check-equal? (hash-ref (hash-ref (car (hash-ref (call rt "prompts/get" (hasheq 'name "a/review" 'arguments (hasheq 'value "x"))) 'messages)) 'content) 'text) "Ax")
(check-exn exn:fail? (lambda () (view base #:adapters (hasheq 'writer (effect-adapter 'idempotent void)))))
(define inherited (view (view base #:adapters (hasheq 'writer a)) #:namespace "again/"))
(check-eq? (hash-ref (hash-ref (interface-adapter-bindings inherited) (car (interface-descriptor-tools inherited))) 'writer) a)

(workflow (later) #:version "1" #:execution task
  (await-input [answer Any] question)
  (perform [result String] #:adapter writer #:policy idempotent "t")
  (text-result result))
(define task-base (make-interface #:tools (list later)))
(define task-interface (mount-interfaces
  (view task-base #:namespace "a/" #:adapters (hasheq 'writer a))
  (view task-base #:namespace "b/" #:adapters (hasheq 'writer b))))
(define task-rt (make-runtime task-interface #:store store))
(define task (call task-rt "tools/call" (hasheq 'name "b/later")))
(define task-id (hash-ref task 'taskId))
(define (await-status runtime expected)
  (let loop ([left 200])
    (define result (call runtime "tasks/get" (hasheq 'taskId task-id)))
    (cond [(equal? (hash-ref result 'status) expected) result]
          [(zero? left) (error 'test "task did not reach ~a: ~s" expected result)]
          [else (sync (alarm-evt (+ (current-inexact-milliseconds) 10))) (loop (sub1 left))])))
(void (await-status task-rt "input_required"))
(void (call task-rt "tasks/update" (hasheq 'taskId task-id 'inputResponses (hasheq 'answer (hasheq 'action "decline")))))
(check-equal? (hash-ref (hash-ref (await-status task-rt "completed") 'result) 'content) (list (text-content "Bt")))
;; Changed adapter code cannot execute a task's unfinished effect on resume.
(set! task-id (hash-ref (call task-rt "tools/call" (hasheq 'name "a/later")) 'taskId))
(void (await-status task-rt "input_required"))
(define incompatible-task-rt (make-runtime
  (view task-base #:namespace "a/" #:adapters (hasheq 'writer (adapter "Changed" "a/2"))) #:store store))
(define before seen)
(define saved-before (load-instance store task-id))
;; Complete executable compatibility is checked before accepting input. This
;; retains the pending row and does not misclassify code drift as an uncertain
;; effect requiring manual recovery.
(check-exn exn:fail:recovery?
  (lambda () (call incompatible-task-rt "tasks/update"
    (hasheq 'taskId task-id 'inputResponses (hasheq 'answer (hasheq 'action "decline"))))))
(check-equal? (load-instance store task-id) saved-before)
(check-equal? (hash-ref (call task-rt "tasks/get" (hasheq 'taskId task-id)) 'status) "input_required")
(check-equal? seen before)
;; A legacy record with no published operation cannot select a sibling by order.
(store-transaction store (lambda ()
  (define instance (load-instance store task-id))
  (void (update-instance! store instance (hash-remove (stored-instance-state instance) 'operationName)))))
(check-exn #rx"ambiguous" (lambda () (call task-rt "tasks/get" (hasheq 'taskId task-id))))
(for ([runtime (list rt changed task-rt incompatible-task-rt)]) (custodian-shutdown-all (runtime-custodian runtime)))
(close-store! store) (delete-file path)
