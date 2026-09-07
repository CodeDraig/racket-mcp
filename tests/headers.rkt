#lang racket/base
(require rackunit mcp/header-schema mcp/schema)
(define schema (object-schema (hasheq 'nested (object-schema (hasheq 'name (hash-set String 'x-mcp-header "Name"))) 'n (hash-set Integer 'x-mcp-header "Count"))))
(check-equal? (length (mirrored-headers schema (hasheq 'nested (hasheq 'name "雪") 'n -2))) 2)
(check-equal? (mirrored-headers schema (hasheq)) '())
(check-exn exn:fail? (lambda () (mirrored-headers schema (hasheq 'n (expt 2 53)))))
(check-exn exn:fail? (lambda () (header-bindings (hasheq 'allOf (list (object-schema (hasheq 'name (hash-set String 'x-mcp-header "Name"))))))))
(check-exn exn:fail? (lambda () (header-bindings (object-schema (hasheq 'x (hash-set String 'x-mcp-header "X") 'y (hash-set String 'x-mcp-header "x"))))))
