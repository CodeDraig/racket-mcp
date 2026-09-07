#lang mcp
(error 'application "manifest inspection must not instantiate application code")
(server #:name (string-append "mani" "fest") #:version "1")
(schema Title String)
(shape Entry [title Title] [count Integer])
(tool (inspect-entry [entry Entry] [verbose Boolean #:default #f])
  #:description "Inspect an entry" #:output Entry
  (text-result "unreachable"))
(resource (entry [id String]) #:uri "entry:///{id}"
  #:description (begin (error 'metadata "must not evaluate") "dynamic")
  #:mime-type "application/json"
  "unreachable")

(workflow (approval [title Title]) #:version "1"
  (checkpoint [saved String] title)
  (await-input [answer Any] (hasheq 'mode "form" 'message "Approve?" 'requestedSchema (object-schema (hasheq))))
  (text-result saved))

(prompt (approval-prompt [title String]) #:workflow "1"
  (checkpoint [saved String] title)
  (list (hasheq 'role "user" 'content (hasheq 'type "text" 'text saved))))

(resource (approval-resource [id String]) #:uri "approval:///{id}" #:workflow "1"
  (perform [saved String] #:adapter save #:policy idempotent id)
  saved)

(workflow (forced-task) #:version "1" #:execution task
  (text-result "done"))

(workflow (optional-task) #:version "1" #:execution task-optional
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Proceed?" 'requestedSchema (object-schema (hasheq))))
  (task-boundary launch)
  (text-result "done"))
