# Reference compiler registration across threads, 2026-09-08

The source-only combined SDK run first exposed two dynamic-require failures.
Tracing showed that the same syntax-spec runtime instance registered schema and
operation compilers but later saw an empty reference-compiler table. A standalone
syntax-spec provider reproduces the failure: first read its syntax-backed export
in a worker, then read it from the main thread. The worker succeeds and the main
thread fails. Merely loading the provider without reading the export, ordinary
nested parameterization, and restoring a parameterization did not reproduce it.

The final patch attaches each delayed default compiler directly to the binding
class transformer. Scoped reference-compiler overrides still take precedence.
There is no new shared default registry or lock. The delayed expression retains
forward-reference behavior and is forced on use. An intermediate module-local
table also fixed the failure, but the lexical representation was selected to keep
defaults with their defining bindings. A reader error in the first lexical probe
was corrected and retained.

The old dependency fails two of the new regression's three checks. The lexical
patch passes all three, all 434 pinned dependency tests in tests and private/test,
45 focused SDK checks on 9.3 including phases 0/1/2, and 32 source-only SDK checks
on 9.2 in the formerly failing order. The package requires locally prepared
syntax-spec-v3 0.1.0.2. Preparation checks every pinned upstream hash before writing
and records hashes for each patched compiler file. The vendor snapshot is intact.
All 14 Go probes, installed dependency setup, and 43 installed checks passed.
Full SDK validation on 9.3 passed 5,792 native checks, 1,301 core schema cases,
86 optional regex cases and Scribble. Logs have trailing
whitespace trimmed. The SDK's broader implementation and release gates remain open.

Two final distribution builds produced the same SHA-256, recorded in
`distribution.sha256`. Distribution contents exclude this evidence directory.
