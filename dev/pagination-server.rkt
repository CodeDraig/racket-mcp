#lang racket/base
(require mcp mcp/stdio)
(define tools
  (for/list ([i (in-range 5)])
    (make-tool (format "tool~a" i) '() (lambda (_) (text-result "ok")) #:description "Pagination fixture")))
(serve-stdio (make-runtime (make-interface #:server (server-descriptor "pagination" "1" "") #:tools tools) #:page-size 2))
