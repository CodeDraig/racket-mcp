#lang racket/base
(provide (struct-out exn:fail:mcp) mcp-error)
(struct exn:fail:mcp exn:fail (code data) #:transparent)
(define (mcp-error code message [data #f]) (raise (exn:fail:mcp message (current-continuation-marks) code data)))
