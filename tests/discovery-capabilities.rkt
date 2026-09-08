#lang racket/base
(require rackunit racket/list mcp mcp/completion)
(define invoked 0)
(tool (operation) (set! invoked (add1 invoked)) (text-result "ok"))
(resource (document) #:uri "document:///one" (set! invoked (add1 invoked)) "ok")
(prompt (message [name String]) (set! invoked (add1 invoked)) (role "user" (text-content name)))
(define complete-name (completion-descriptor message 'name (lambda (_prefix _context) '("Ada"))))
(define (discover interface #:store [store #f])
  (define response
    (dispatch-message (make-runtime interface #:store store)
      (hasheq 'jsonrpc "2.0" 'id 1 'method "server/discover"
              'params (hasheq '_meta (request-meta)))))
  (check-false (hash-has-key? response 'error))
  (hash-ref (hash-ref response 'result) 'capabilities))
(test-case "discovery reflects installed declaration families without invoking handlers"
  (for* ([tools? '(#f #t)] [resources? '(#f #t)] [prompts? '(#f #t)]
         [completion? (if prompts? '(#f #t) '(#f))])
    (define caps
      (discover (make-interface #:tools (if tools? (list operation) '())
                                #:resources (if resources? (list document) '())
                                #:prompts (if prompts? (list message) '())
                                #:completions (if completion? (list complete-name) '()))))
    (define expected
      (append (if tools? '(tools) '()) (if resources? '(resources) '())
              (if prompts? '(prompts) '()) (if completion? '(completions) '())))
    (check-equal? (sort (hash-keys caps) symbol<?) (sort expected symbol<?))
    (for ([family (in-list '(tools resources prompts))] #:when (hash-has-key? caps family))
      (check-equal? (hash-ref (hash-ref caps family) 'listChanged) #t))
    (when resources? (check-equal? (hash-ref (hash-ref caps 'resources) 'subscribe) #t)))
  (check-equal? invoked 0))
(test-case "removing declarations also removes dependent advertised facilities"
  (define interface
    (make-interface #:tools (list operation) #:resources (list document)
                    #:prompts (list message) #:completions (list complete-name)))
  (check-equal? (discover (view interface #:exclude '("message")))
                (hasheq 'tools (hasheq 'listChanged #t)
                        'resources (hasheq 'listChanged #t 'subscribe #t)))
  (check-equal? (discover (view interface #:exclude '("operation" "document" "message")))
                (hasheq)))
(workflow (background) #:version "1" #:execution task
  (text-result "done"))
(test-case "storage alone does not advertise Tasks and discovery queues no work"
  (define store (open-memory-store))
  (dynamic-wind void
    (lambda ()
      (check-equal? (discover (make-interface) #:store store) (hasheq))
      (define interface (make-interface #:tools (list background)))
      (define caps (discover interface #:store store))
      (check-equal? (hash-ref caps 'extensions)
                    (hasheq 'io.modelcontextprotocol/tasks (hasheq)))
      (check-equal? (discover (view interface #:exclude '("background")) #:store store) (hasheq))
      (check-equal? (list-instances store) '()))
    (lambda () (close-store! store))))
