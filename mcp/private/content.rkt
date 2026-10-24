#lang racket/base

(provide text-content text-result structured-result error-result message role image-content audio-content)
(define (text-content text) (hasheq 'type "text" 'text text))
(define (text-result text) (hasheq 'resultType "complete" 'content (list (text-content text))))
(define (structured-result value #:content [content '()]) (hasheq 'resultType "complete" 'content content 'structuredContent value))
(define (error-result message) (hash-set (text-result message) 'isError #t))
(define (message role content) (hasheq 'role role 'content content))
(define (role who . contents) (map (lambda (content) (message who content)) contents))
(define (image-content data mime) (hasheq 'type "image" 'data data 'mimeType mime))
(define (audio-content data mime) (hasheq 'type "audio" 'data data 'mimeType mime))
