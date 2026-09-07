#lang mcp
(server #:name "multi-content" #:version "0.1.0")
(resource (pages) #:uri "docs:///pages"
  (resource-contents "First page" "Second page"))
(tool (show-pages)
  #:description "Embed both pages in their original order."
  (structured-result (hasheq) #:content (list (embed (pages)))))
(prompt (read-pages)
  (role "user" (embed (pages))))
