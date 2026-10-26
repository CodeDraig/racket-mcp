#lang info
(define collection 'multi)
(define version "0.1")
;; Original project work; bundled material retains its own licenses as detailed
;; in THIRD-PARTY-NOTICES.md.
(define license 'MIT)
(define deps '("base" "compiler-lib" "db-lib" "web-server-lib" "net-lib"
               ("https://github.com/CodeDraig/racket-mcp.git?path=packages/mcp-syntax-spec-v3#main"
                #:version "0.1.0.2")))
(define build-deps '("rackunit-lib" "racket-doc" "scribble-lib"))
(define test-omit-paths '("vendor" "packages" ".racket" ".cache" "test-artifacts"))
(define compile-omit-paths '("vendor" "packages" ".racket" ".cache" "test-artifacts"))
(define setup-collects '("mcp"))
