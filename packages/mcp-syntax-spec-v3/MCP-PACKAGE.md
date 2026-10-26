# mcp-syntax-spec-v3

An MCP-specific patched copy of syntax-spec v3, version 0.1.0.2.
Upstream: https://github.com/michaelballantyne/syntax-spec/tree/4ae36610804b58e8f023574bfdcba1b5ae4f7bcd

Package and collection name: `mcp-syntax-spec-v3`. Use `(require mcp-syntax-spec-v3)`.
The distinct collection can coexist with upstream `syntax-spec-v3`; this is
not an upstream release or a replacement for that package.

Changes preserve module-level declaration scopes, compare persistent bindings
at their compiler phase, and attach delayed reference defaults to binding-class
transformers. Collection references in source, tests, and manuals are renamed.
The compiler behavior patches are the same as the SDK's previously tested
local version 0.1.0.2. MCP-PATCH.json records provenance and generated file hashes.

This directory is an installable single-collection Racket package. From its
parent directory: `raco pkg install --auto ./mcp-syntax-spec-v3`.
No Python preparation step is needed by package consumers.

Maintainers reproduce it from the racket-mcp repository root with
`python3 scripts/prepare-syntax-spec.py`, verify it with `--check`, and optionally
write a reproducible source ZIP with `--archive PATH`.
The original snapshot under vendor/syntax-spec-v3 is never changed.

Original upstream copyright and license notices are retained. This distribution
uses the MIT option for the upstream Apache-2.0-or-MIT material; Racket-MIT.txt
contains that license text. The upstream tests/dsls/tiny-hdl sources retain their
MPL-2.0 license and its included LICENSE file. See LICENSE and those source files.
The upstream README.md is retained as upstream documentation.
