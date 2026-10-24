#lang racket/base
(require "private/presentation-content.rkt" "private/resource-renderer.rkt")
(provide text-presentation json-presentation binary-presentation resource-contents resource-content presentation-content presentation-contents)

(provide (struct-out resource-renderer) make-resource-renderer make-text-renderer make-json-renderer make-binary-renderer
         apply-resource-renderer renderer-fingerprint)
