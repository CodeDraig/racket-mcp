#lang racket/base
(require rackunit racket/list racket/file racket/async-channel mcp mcp/upstream)
(define request-form (hasheq 'method "elicitation/create" 'params
  (hasheq 'mode "form" 'message "Name?" 'requestedSchema (object-schema (hasheq 'name String)))))
(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities
                                  (hasheq 'tools (hasheq) 'resources (hasheq) 'prompts (hasheq)))
          'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object"))))
          'resources/list (hasheq 'resources (list (hasheq 'name "doc" 'uri "up:///doc")))
          'resources/templates/list (hasheq 'resourceTemplates '())
          'prompts/list (hasheq 'prompts (list (hasheq 'name "ask")))))
(define directory (make-temporary-file "mcp-upstream-bridge-~a" 'directory))
(define bridge (make-upstream-bridge #:identity "service" #:version "1" #:credential-id (lambda (_) "account-a")))
(define capabilities (hasheq 'elicitation (hasheq)))
(define (exercise store)
  (define calls '())
  (define (peer method params)
    (define listing (hash-ref snapshot (string->symbol method) #f))
    (cond [listing listing]
          [else
           (set! calls (append calls (list (cons method params))))
           (if (not (hash-has-key? params 'requestState))
               (hasheq 'resultType "input_required" 'requestState "remote-state"
                       'inputRequests (hasheq 'first request-form 'second request-form))
               (begin
                 (check-equal? (hash-ref params 'requestState) "remote-state")
                 (check-equal? (hash-count (hash-ref params 'inputResponses)) 2)
                 (case (string->symbol method)
                   [(tools/call) (text-result "done")]
                   [(resources/read) (hasheq 'resultType "complete" 'contents
                     (list (hasheq 'uri "up:///doc" 'text "done")))]
                   [(prompts/get) (hasheq 'resultType "complete" 'messages
                     (list (hasheq 'role "user" 'content (text-content "done"))))])))]))
  (define iface (make-upstream-interface snapshot peer #:bridge bridge))
  (define rt (make-runtime (view iface #:namespace "local-" #:uris (hash "up:///doc" "local:///doc")) #:store store))
  (define (call method params [principal "alice"])
    (dispatch rt method (hash-set params '_meta (request-meta #:capabilities capabilities)) #:principal principal))
  (dynamic-wind void
    (lambda ()
      (for ([method '("tools/call" "resources/read" "prompts/get")]
            [params (list (hasheq 'name "local-work") (hasheq 'uri "local:///doc") (hasheq 'name "local-ask"))])
        (set! calls '())
        (define first (call method params))
        (check-equal? (hash-ref first 'resultType) "input_required")
        (check-not-equal? (hash-ref first 'requestState) "remote-state")
        (define ids (hash-keys (hash-ref first 'inputRequests)))
        (check-equal? (length ids) 2)
        (check-false (member 'first ids))
        (define retry (hash-set params 'requestState (hash-ref first 'requestState)))
        (check-exn exn:fail? (lambda () (call method retry "bob")))
        (check-equal? (length calls) 1)
        (define partial (call method (hash-set retry 'inputResponses (hasheq (car ids) (hasheq 'action "decline")))))
        (check-equal? (hash-count (hash-ref partial 'inputRequests)) 1)
        (check-equal? (length calls) 1)
        (check-exn exn:fail:mcp?
          (lambda () (call method (hash-set retry 'inputResponses (hasheq (car ids) (hasheq 'action "cancel"))))))
        (define final (call method (hash-set retry 'inputResponses (hasheq (cadr ids) (hasheq 'action "cancel")))))
        (check-equal? (hash-ref final 'resultType) "complete")
        (check-equal? (length calls) 2)
        (check-equal? (call method retry) final)
        (check-equal? (length calls) 2)
        (when (equal? method "resources/read")
          (check-equal? (hash-ref (car (hash-ref final 'contents)) 'uri) "local:///doc"))))
    (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
(dynamic-wind void
  (lambda () (exercise (open-memory-store)) (exercise (open-sqlite-store (build-path directory "state.sqlite"))))
  (lambda () (delete-directory/files directory)))
