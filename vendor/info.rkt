#lang info
;; Pinned inputs are data belonging to independent upstream packages. Prepare
;; and install the language dependency separately; do not compile it as MCP.
(define compile-omit-paths 'all)
(define test-omit-paths 'all)
