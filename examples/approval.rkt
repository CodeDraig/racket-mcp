#lang mcp
(server #:name "approval" #:version "0.1.0")
(workflow (approve [name String]) #:version "1"
  (checkpoint [greeting String] (string-append "Hello, " name))
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'approved Boolean))))
  (structured-result (hasheq 'greeting greeting 'answer answer)))
