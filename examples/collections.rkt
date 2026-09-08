#lang mcp
(require "extensions/collection.rkt")
(server #:name "collections" #:version "0.1.0")

;; Each extension invocation owns its helper binding and completion target.
(collection books #:uri "book:///{id}"
  #:entries (hash "a b" "First book" "two" "Second book"))
(collection articles #:uri "article:///{id}"
  #:entries (hash "a b" "First article" "essay" "Second article"))
