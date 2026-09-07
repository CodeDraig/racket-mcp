#lang mcp
(server #:name "greeter" #:version "0.1.0")
(tool (greet [name String])
  #:description "Greet someone by name."
  (text-result (string-append "Hello, " name)))
