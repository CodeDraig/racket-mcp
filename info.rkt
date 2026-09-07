#lang info
(define collection 'multi)
(define version "0.1")
(define deps '("base" "db-lib" "web-server-lib" "net-lib" "syntax-spec-v3"))
(define build-deps '("rackunit-lib" "racket-doc" "scribble-lib"))
(define test-omit-paths '("vendor" ".racket" ".cache" "test-artifacts"))
(define compile-omit-paths '("vendor" ".racket" ".cache" "test-artifacts"))
(define setup-collects '("mcp"))
