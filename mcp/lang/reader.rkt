#lang s-exp syntax/module-reader
mcp/lang
#:wrapper1 (lambda (read) (install-module-observation!) (read))
(require "../private/module-observation.rkt")
