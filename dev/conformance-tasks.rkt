#lang mcp
(server #:name "racket-mcp-tasks-conformance" #:version "0.1.0")
(tool (greet [name String]) #:description "Return a synchronous greeting."
  (text-result (string-append "Hello, " name "!")))
(workflow (slow_compute [seconds (hasheq 'type "integer" 'minimum 0 'maximum 60)] [label String])
  #:version "1" #:execution task-optional #:description "Wait for the requested duration."
  (checkpoint [waited Boolean] (begin (sleep seconds) #t))
  (text-result (string-append "Computed " label)))
(workflow (failing_job) #:version "1" #:execution task #:description "Report a tool execution error."
  (error-result "Intentional tool error"))
(workflow (protocol_error_job) #:version "1" #:execution task #:description "Raise a protocol execution failure."
  (error 'protocol_error_job "Intentional execution failure"))
(define confirm-form (hasheq 'mode "form" 'message "Confirm?"
  'requestedSchema (object-schema (hasheq 'confirm Boolean 'name String) #:required '("confirm"))))
(workflow (confirm_delete [filename String]) #:version "1" #:execution task #:description "Ask for confirmation; no files are deleted."
  (await-input [confirmation Any] confirm-form)
  (text-result (string-append "Confirmed " filename)))
(workflow (multi_input) #:version "1" #:execution task #:description "Request two independent confirmations."
  (await-input ([first Any confirm-form] [second Any confirm-form]))
  (text-result "Both responses received"))
