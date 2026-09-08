#lang s-exp syntax/module-reader
"language.rkt"
#:wrapper1 (lambda (read) (install!) (read))
(require "observer.rkt")
