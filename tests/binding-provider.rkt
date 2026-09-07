#lang racket/base
(require mcp)
(provide Label operation document)
(schema Label (hasheq 'type "string" 'minLength 1))
(tool (operation [label Label]) (text-result label))
(resource (document [id Label]) #:uri "document:///{id}" id)
