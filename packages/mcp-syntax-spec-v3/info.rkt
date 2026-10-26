#lang info

(define name "mcp-syntax-spec-v3")
(define collection "mcp-syntax-spec-v3")
(define version "0.1.0.2")
(define license '(Apache-2.0 OR MIT))
(define deps '("base"
               "version-case"
               "syntax-classes-lib"
               "rackunit-lib"))
(define build-deps '("racket-doc" "scribble-lib" "drracket" "typed-racket-lib"))
(define scribblings '(("scribblings/main.scrbl" (multi-page) (experimental) "mcp-syntax-spec-v3")))
(define compile-omit-paths '("design" "demos"))
(define test-omit-paths '("design" "demos"))

(define pkg-desc "MCP-specific syntax-spec v3 with phase and reference-binding fixes")
