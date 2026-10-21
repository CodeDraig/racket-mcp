#lang racket/base
(require "../json.rkt" "render-provenance.rkt")
(provide persistent-json)
;; Use the same value representation before and after persistence. Preserve
;; SDK-owned rendering marks in their separate, trusted provenance channel.
(define (persistent-json value)
  (restore-render-provenance (string->json (json->string value)) (render-provenance value)))
