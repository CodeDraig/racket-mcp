#lang racket/base
(require "private/resource-cache.rkt" "private/change-outbox.rkt")
(provide cache-clock (struct-out cache-partition) make-resource-cache cache-ref! invalidate-keys! (struct-out committed-result)
         record-committed-change! drain-change-outbox!)
