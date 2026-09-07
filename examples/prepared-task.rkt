#lang mcp
(server #:name "prepared-task" #:version "0.1.0")
(workflow (greet-later) #:version "1" #:execution task
  #:description "Gather a name before creating a background greeting task."
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Who should we greet?"
            'requestedSchema (object-schema (hasheq 'name String))))
  (if (equal? (hash-ref answer 'action) "accept")
      (begin
        (task-boundary greeting)
        (text-result (string-append "Hello, " (hash-ref (hash-ref answer 'content) 'name))))
      (text-result (string-append "Greeting " (hash-ref answer 'action)))))
