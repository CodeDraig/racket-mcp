# Retained identities in executable capture, 2026-09-08

Capture prefers producer identities embedded in observed code and reads retained
identities from already-declared dependencies. It never reads replacement files
to infer loaded code. A preloaded unstamped helper stays unresolved even after its
file is replaced with a stamped artifact. The public loader follows the same
identity preference for observed bootstrap code; explicit runtime identity remains
required for the unresolved baseline.

Three new cases prove the stamped/unstamped distinction and durable behavior with
SQLite. A helper is stamped and loaded before capture. After an invocation pauses,
its artifact is replaced and a new namespace loads the new helper. The new captured
workflow rejects the old continuation before writing the completion marker. The
old captured workflow still completes with the old implementation; fresh work uses
the new one. The helper digest is checked against the original producer identity
and must be absent from unresolved dependencies before explicit fixture identities
are supplied for the remaining runtime baseline.

The initial existing suite passed 51 checks. The new cases passed on 9.3; the
five-file capture/loader/restart suite passed 68 checks on 9.2. All 14 Go probes
passed. Installed package dependency setup and 54 installed checks also passed.
Full Racket 9.3 verification passed compilation, 5,942 native checks, all 1,301
core schema cases, all 86 optional regex cases and Scribble. The new SQLite
case uses distinct namespaces in one process; separate-process restart evidence
comes from the existing captured-build-restart suite, not from that new case.

Commands: raco make/raco test on retained-capture, executable-capture, loader,
captured-submodules and captured-build-restart; scripts/check.sh;
scripts/check-interop.sh. Racket 9.2 uses the isolated compiled root, except the
helper fixture explicitly loads its adjacent artifact. Logs trim trailing whitespace.

Default workflow build-context creation/sealing and the full SDK release remain
unfinished. These are trusted producer identities, not signatures.

The separate kernel-bootstrap probe is an experiment, not SDK startup code. It
uses a raw #%kernel entry and installs evaluation observation before requiring the
SDK. Initial attempts used and/hash-keys, unavailable in that language. A further
trace initially overwrote parent records with separately loaded submodules; the
final probe assigns their compiled suffixes before recording. Final 9.2 and 9.3
traces show only predefined modules missing from the greeter dependency graph.
No ordinary file module remains missing in those traces. The prototype does not
yet seed the SDK's registry-scoped observer, handle multiple registries, identify
the running native image portably, or establish default workflow build contexts.
