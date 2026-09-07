#lang mcp
(require "extensions/collection.rkt")
(server #:name "library" #:version "0.1.0")
(collection books #:uri "book:///{id}" #:entries (hash "one" "First book" "two" "Second book"))
