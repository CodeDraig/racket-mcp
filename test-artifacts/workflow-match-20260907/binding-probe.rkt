#lang racket/base
(require racket/match mcp "../../examples/extensions/checkpoint-copy.rkt")
(workflow (copy-match [value String]) #:version "1"
 (match value
  [captured (checkpoint-copy [saved String] captured) (text-result saved)]))
