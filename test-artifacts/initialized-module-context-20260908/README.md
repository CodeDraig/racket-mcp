# Shared initialized workflow contexts

The compiler boundary creates one lexical context for a module and finalizes it
after expanded initialization. Construction sites and factories share that
context, explicit enclosing loaders retain ownership, and generated workflow
construction participates when the boundary is installed. A guarded seal requires
the initialized flag. Late failure and repeated dynamic-require leave it false.

Five new cases include actual workflow construction, rejected unsealed execution,
explicit sealing, and successful local dispatch. Late named dynamic declaration
coverage uses the observation API's declared-module identity. Fixture baseline
identities are explicit test data, not automatic runtime provenance. Default
language integration and the production runtime identity policy remain open.

Initial focused verification encountered a stale compiled restart worker after
the sealing function's keyword signature changed. Corrected verification makes
that dynamic fixture explicitly; full and installed setup compile all test files.
The initial dynamic-eval fixture also required a lexical module binding and an
explicit declared identity; those fixture corrections preceded broader checks.

Commands use scripts/racket-env.sh, an isolated 9.2 compiled root, and the 9.3
package home. The full command is sh scripts/check.sh. Focused checks cover the
16 files named in their logs, including module contexts, workflow/control flow,
phases/extensions, manifests, restart and command paths. Installed verification
unsets PLTCOLLECTS and runs raco setup --no-docs --check-pkg-deps before those files.
Final source verification passed all 196 focused checks on Linux Racket 9.2,
Linux Racket 9.3, and the installed 9.3 package. Dependency setup and all 14 Go
interoperability probes passed. Full Linux 9.3 verification passed 6,148 native
tests, all 1,301 core schema cases, all 86 optional regex cases, and Scribble.

The source ZIP was built twice and byte-compared; distribution-SHA256SUMS records
its digest. Stored logs have trailing whitespace removed only. The GitHub run
for the preceding pushed commit 1f1f82c completed with startup_failure and zero
jobs; the saved API responses establish no native macOS/Windows verification.
The full SDK goal, default integration, and runtime identity policy remain open.
