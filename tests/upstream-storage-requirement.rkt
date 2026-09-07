#lang racket/base
(require rackunit racket/file mcp mcp/upstream mcp/cli)

(define snapshot
  (hasheq 'server/discover (hasheq 'supportedVersions '("2026-07-28") 'capabilities
                                  (hasheq 'tools (hasheq) 'resources (hasheq) 'prompts (hasheq)))
          'tools/list (hasheq 'tools (list (hasheq 'name "work" 'inputSchema (hasheq 'type "object"))))
          'resources/list (hasheq 'resources (list (hasheq 'name "doc" 'uri "up:///doc")))
          'resources/templates/list (hasheq 'resourceTemplates '())
          'prompts/list (hasheq 'prompts (list (hasheq 'name "ask")))))
(define calls 0)
(define (unexpected . args) (set! calls (add1 calls)) (error 'test "callback ran during construction or serving preflight"))
(define bridge (make-upstream-bridge #:identity "service" #:version "1" #:credential-id unexpected))
(define upstream (make-upstream-interface snapshot unexpected #:bridge bridge))
(define ordinary (make-upstream-interface snapshot unexpected))
(define (executable iface)
  ;; A raw descriptor rebuild preserves procedure metadata as well as view copies.
  (interface-descriptor (server-descriptor "test" "1" #f)
                        (interface-descriptor-tools iface) (interface-descriptor-resources iface)
                        (interface-descriptor-prompts iface) (interface-descriptor-completions iface)))
(define directory (make-temporary-file "mcp-bridge-storage-~a" 'directory))
(dynamic-wind void
  (lambda ()
    (check-true (interface-requires-state? upstream))
    (check-false (interface-requires-state? ordinary))
    (check-false (interface-requires-state? (view upstream #:include '())))
    (for ([name '("work" "doc" "ask")])
      (define isolated (view upstream #:include (list name) #:namespace "local-"
                             #:uris (hash "up:///doc" "local:///doc")))
      (define mounted (mount-interfaces isolated))
      (check-true (interface-requires-state? mounted))
      (check-true (interface-requires-state? (executable mounted)))
      (parameterize ([current-input-port (open-input-string "")]
                     [current-output-port (open-output-string)])
        (check-exn #rx"explicit --state file" (lambda () (serve-interface (executable mounted))))))
    (parameterize ([current-input-port (open-input-string "")]
                   [current-output-port (open-output-string)])
      (serve-interface (executable upstream) #:state (build-path directory "bridge.sqlite"))
      (serve-interface (executable ordinary))
      (serve-interface (executable (view upstream #:include '()))))
    (check-true (file-exists? (build-path directory "bridge.sqlite")))
    (check-equal? calls 0))
  (lambda () (delete-directory/files directory)))
