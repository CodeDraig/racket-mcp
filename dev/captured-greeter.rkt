#lang racket/base
(require racket/runtime-path mcp/loader mcp/cli)
(define-runtime-path greeter "../examples/greeter.rkt")
(module+ main
  ;; This explicit identity belongs to the controlled interoperability fixture;
  ;; deployments supply an identity for their own immutable runtime distribution.
  (serve-interface
    (load-interface greeter #:runtime-build-id "interop-fixture-sdk-and-runtime/1")))
