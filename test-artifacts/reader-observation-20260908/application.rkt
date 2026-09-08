#lang reader "reader.rkt"
(require "helper.rkt")
(module configure-runtime racket/base
  (require "observer.rkt")
  (install!))
(displayln (greeting))
