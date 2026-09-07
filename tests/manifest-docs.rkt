#lang racket/base
(require rackunit racket/string racket/runtime-path mcp/cli)
(define-runtime-path fixture "manifest-rich.rkt")
(define text (manifest->markdown (read-manifest fixture) #:title "Rich interface"))
(for ([expected '("# Interface: ` Rich interface `" "Inspect an entry"
                   "## server ` (string-append \"mani\" \"fest\") `"
                   "### Arguments" "` verbose ` — optional" "default: ` false `"
                   "### Input schema" "### Output schema" "```json\n"
                   "dynamic expression ` (begin (error" "**mime\\-type:** ` \"application/json\" `"
                   "Runtime requirements: ` workflow-storage `, ` adapters `."
                   "Client capabilities required by declared workflow stages:"
                   "Optional client capabilities:"
                   "execution has a fallback when absent."
                   "### Workflow stages" "1. ` saved ` — effect; adapter ` save `; policy ` idempotent `")])
  (check-true (string-contains? text expected) expected))
(check-false (string-contains? text "Metadata requires runtime inspection"))
(check-equal? (manifest->markdown (read-manifest fixture) #:title "Rich interface") text)
(define-runtime-path example "../examples/multi-content.rkt")
(check-true (string-contains? (manifest->markdown (read-manifest example)) "### Resource references"))
(define-runtime-path completion "../examples/library.rkt")
(check-true (string-contains? (manifest->markdown (read-manifest completion)) "Completes argument"))
(define synthetic
  (list (hasheq 'kind 'tool 'name "name`with\r\nbreak"
                'metadata (hasheq 'description (hasheq 'known? #t 'value "<script>\n# title\n- item")
                                  'annotations (hasheq 'known? #t 'value (hasheq 'readOnlyHint #f)))
                'input-schema (hasheq 'known? #t 'value (hasheq 'examples (list "```")))
                'arguments (list (hasheq 'name 'x 'required #f
                                         'schema (hasheq 'known? #t 'value #f)
                                         'default (hasheq 'known? #f 'expression "(compute earlier)")
                                         'codec (hasheq 'known? #f 'expression "codec"))))))
(define escaped (manifest->markdown synthetic))
(check-true (string-contains? escaped "`` name`with\\n\\nbreak ``"))
(check-false (string-contains? escaped "<script>"))
(check-true (string-contains? escaped "\\<script\\>\n\\# title\n\\- item"))
(check-true (string-contains? escaped "````json\n"))
(check-true (string-contains? escaped "\"readOnlyHint\":false"))
(check-true (string-contains? escaped "schema: ` false `"))
(check-true (string-contains? escaped "default: dynamic expression ` (compute earlier) `"))
(check-true (string-contains? escaped "codec: dynamic expression ` codec `"))
(check-exn exn:fail:contract? (lambda () (manifest->markdown #f)))
