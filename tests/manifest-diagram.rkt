#lang racket/base
(require rackunit racket/string racket/runtime-path mcp/cli)
(define (stage id kind [targets #f] [policy #f])
  (hasheq 'id id 'kind kind 'adapter-or-targets targets 'policy policy))
(define workflow
  (hasheq 'kind 'workflow 'name 'approve
          'resource-references (list (hasheq 'name 'document 'source "local"))
          'workflow-stages
          (list (stage 'saved 'checkpoint) (stage 'choice 'branch '(save request))
                (stage 'save 'effect 'database 'idempotent) (stage 'join 'jump 'done)
                (stage 'request 'input) (stage 'done 'complete))))
(define resource (hasheq 'kind 'resource 'name 'document 'source "local"))
(define graph (manifest->mermaid (list workflow resource)))
(for ([edge '("d0 -.->|references| d1" "d0 -.->|start| d0_s0"
              "d0_s0 --> d0_s1" "d0_s1 -->|branch 0| d0_s2"
              "d0_s1 -->|branch 1| d0_s4" "d0_s2 --> d0_s3"
              "d0_s3 -->|join| d0_s5" "d0_s4 --> d0_s5"
              "d0_s2 -.->|idempotent| d0_a0")])
  (check-true (string-contains? graph edge)))
(check-false (string-contains? graph "d0_s1 --> d0_s2"))
(check-false (string-contains? graph "d0_s3 --> d0_s4"))
(check-false (string-contains? graph "d0_s5 -->"))
(check-equal? (manifest->mermaid (list workflow resource)) graph)
(define external (manifest->mermaid (list workflow (hash-set resource 'source "other"))))
(check-true (string-contains? external "external or unresolved resource: document"))
(check-true (string-contains? external "d0 -.->|references| r0"))
(check-false (string-contains? external "d0 -.->|references| d1"))
(check-true (string-contains? (manifest->mermaid (list workflow resource resource)) "ambiguous resource: document"))
(define hostile (manifest->mermaid (list (hasheq 'kind 'tool 'name "\"]\nclick d0 evil\n<script>&#34;`"))))
(check-equal? (length (string-split hostile "\n")) 4)
(check-true (string-contains? hostile "#34;#93;"))
(check-true (string-contains? hostile "#60;script#62;#38;#35;34#59;#96;"))
(check-false (string-contains? hostile "<script>"))
(check-exn #rx"unresolved workflow target"
           (lambda () (manifest->mermaid (list (hash-set workflow 'workflow-stages (list (stage 'jump 'jump 'absent)))))))
(check-exn #rx"duplicate workflow stage"
           (lambda () (manifest->mermaid (list (hash-set workflow 'workflow-stages (list (stage 'x 'input) (stage 'x 'complete)))))))
(define-runtime-path fixture "manifest-rich.rkt")
;; This application's top-level raises if instantiated.
(define real (manifest->mermaid (read-manifest fixture)))
(check-true (string-contains? real "checkpoint: saved"))
(check-true (string-contains? real "adapter: save"))
