#lang racket/base
(require mcp-syntax-spec-v3 (for-syntax racket/base syntax/parse))
(provide (for-syntax declaration-extension workflow-extension
                     expand-declaration-extension expand-workflow-extension))
;; Classes and expanders remain private. Public definitions select a supported
;; extension kind, not a compiler representation or a mutable registration table.
(syntax-spec
 (extension-class declaration-extension #:description "MCP declaration extension")
 (extension-class workflow-extension #:description "MCP workflow extension")
 (nonterminal declaration-source
   #:allow-extension declaration-extension
   form:expr)
 (nonterminal workflow-source
   #:allow-extension workflow-extension
   form:expr))
(begin-for-syntax
  (define expand-declaration-extension (nonterminal-expander declaration-source))
  (define expand-workflow-extension (nonterminal-expander workflow-source)))
