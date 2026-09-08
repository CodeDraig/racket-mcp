#lang mcp
(require "lang-marker.rkt"
         (rename-in (submod "../../tests/workflow-effect-bindings.rkt" extensions)
                    [assert-effect scope] [write save]))
(server #:name "effect-language" #:version "1")
(workflow (write-message [writer String]) #:version "1"
  (scope before writer #f)
  (save saved writer writer)
  (scope after writer #t)
  (text-result saved))
(set-box! loaded #t)
