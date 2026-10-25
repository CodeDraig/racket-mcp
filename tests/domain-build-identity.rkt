#lang racket/base
(require rackunit racket/file mcp)
(define meta (request-meta #:capabilities (hasheq 'elicitation (hasheq))))
(define directory (make-temporary-file "domain-build-~a" 'directory))
(define application (build-path directory "application.rkt"))
(define helper (build-path directory "helper.rkt"))
(define (write-helper value)
  (call-with-output-file helper #:exists 'truncate
    (lambda (out) (fprintf out "#lang racket/base\n(provide helper)\n(define (helper) ~s)\n" value))))
(dynamic-wind void
  (lambda ()
    (call-with-output-file application
      (lambda (out)
        (display "#lang mcp
(require \"helper.rkt\")
(define form (hasheq 'mode \"form\" 'message \"Continue?\" 'requestedSchema (object-schema (hasheq))))
(prompt (conversation) #:workflow \"1\"
  (await-input [answer Any] form)
  (role \"user\" (text-content (helper))))
(resource (report) #:uri \"report:///\" #:workflow \"1\"
  (await-input [answer Any] form)
  (helper))
" out)))
    (write-helper "before")
    (define before (load-interface application #:runtime-build-id "test-bootstrap/1"))
    (define store (open-memory-store))
    (define rt (make-runtime before #:store store))
    (dynamic-wind void
      (lambda ()
        (define requests (list (cons "prompts/get" (hasheq '_meta meta 'name "conversation"))
                               (cons "resources/read" (hasheq '_meta meta 'uri "report:///"))))
        (define resumes
          (for/list ([request (in-list requests)])
            (define pending (dispatch rt (car request) (cdr request)))
            (cons (car request)
                  (hash-set* (cdr request) 'requestState (hash-ref pending 'requestState)
                             'inputResponses (hasheq 'answer (hasheq 'action "decline"))))))
        (define saved (list-instances store))
        ;; Simulate the old dispatcher stripping a captured descriptor. Its saved
        ;; state lacks sufficient identity and must never be silently upgraded.
        (define legacy-interface
          (make-interface
            #:prompts (for/list ([p (in-list (interface-descriptor-prompts before))])
                        (struct-copy prompt-descriptor p
                          [workflow (struct-copy workflow-descriptor (prompt-descriptor-workflow p))]))
            #:resources (for/list ([r (in-list (interface-descriptor-resources before))])
                          (struct-copy resource-descriptor r
                            [workflow (struct-copy workflow-descriptor (resource-descriptor-workflow r))]))))
        (define legacy (make-runtime legacy-interface #:store store))
        (for ([request (in-list requests)])
          (define pending (dispatch legacy (car request) (cdr request)))
          (define snapshot (list-instances store))
          (check-exn exn:fail:recovery?
            (lambda () (dispatch rt (car request)
                          (hash-set* (cdr request) 'requestState (hash-ref pending 'requestState)
                                     'inputResponses (hasheq 'answer (hasheq 'action "decline"))))))
          (check-equal? (list-instances store) snapshot))
        (custodian-shutdown-all (runtime-custodian legacy))
        (set! saved (list-instances store))
        (write-helper "after")
        (define changed (make-runtime (load-interface application #:runtime-build-id "test-bootstrap/1") #:store store))
        (for ([request (in-list resumes)])
          (check-exn exn:fail:recovery? (lambda () (dispatch changed (car request) (cdr request)))))
        (check-equal? (list-instances store) saved)
        ;; Original captured code still resumes, despite the changed source file.
        (for ([request (in-list resumes)])
          (define result (dispatch rt (car request) (cdr request)))
          (check-equal? (hash-ref result 'resultType) "complete")
          (check-true (regexp-match? #rx"before" (json->string result))))
        (custodian-shutdown-all (runtime-custodian changed)))
      (lambda () (custodian-shutdown-all (runtime-custodian rt)) (close-store! store))))
  (lambda () (delete-directory/files directory)))

(test-case "domain dispatch preserves separately declared build identities"
  (define form (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq))))
  (define (interface identity)
    (call-with-build-identity identity
      (lambda ()
        (prompt (p) #:workflow "1" (await-input [answer Any] form) (role "user" (text-content "done")))
        (resource (r) #:uri "r:///" #:workflow "1" (await-input [answer Any] form) "done")
        (make-interface #:prompts (list p) #:resources (list r)))))
  (define store (open-memory-store))
  (define one (make-runtime (interface "application/1") #:store store))
  (define two (make-runtime (interface "application/2") #:store store))
  (dynamic-wind void
    (lambda ()
      (for ([method '("prompts/get" "resources/read")]
            [params (list (hasheq '_meta meta 'name "p") (hasheq '_meta meta 'uri "r:///"))])
        (define pending (dispatch one method params))
        (define resume (hash-set* params 'requestState (hash-ref pending 'requestState)
                                  'inputResponses (hasheq 'answer (hasheq 'action "decline"))))
        (define saved (list-instances store))
        (check-exn exn:fail:recovery? (lambda () (dispatch two method resume)))
        (check-equal? (list-instances store) saved)
        (check-equal? (hash-ref (dispatch one method resume) 'resultType) "complete")))
    (lambda () (custodian-shutdown-all (runtime-custodian one))
               (custodian-shutdown-all (runtime-custodian two)) (close-store! store))))
