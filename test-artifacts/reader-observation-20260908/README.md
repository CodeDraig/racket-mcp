# Reader and runtime observation, 2026-09-08

The private installer and actual MCP reader/language hooks capture code evaluated
after installation. The runtime hook also covers compiled dynamic-require, where
the reader does not run. Installation is idempotent and preserves a caller's
evaluator. Ten new cases and three existing capture/bootstrap suites passed 49
checks on each of Racket 9.2 and 9.3. All 14 Go probes passed. Installed package
dependency setup and the same 49 checks passed. Full Racket 9.3 validation passed
compilation, 5,931 native checks, 1,301 core schema cases, 86 optional regex cases
and Scribble. The SDK/documentation/test source files matched the verified
installed distribution byte for byte.

Initial custom-reader probes logged only compiled evaluator inputs and appeared
to miss source dependencies. Logging syntax inputs revealed that the hook was
already active. The production observer compiles those source modules once and
records the same objects it evaluates. Traces labelled language-* use both reader
and runtime hooks; earlier traces precede the runtime hook. The retained small
language fixtures are the final combined form. Use fresh compiled directories
when repeating the source cases, then raco make all five fixture files before
repeating compiled cases. These probes were followed by the authored regression
suite against the actual #lang mcp implementation.

Preloaded helpers remain unknown; the test deliberately loads one before the
hook and verifies that a later edit does not become purported code evidence.
Default durable fingerprints are not yet sealed from these observations. The
full automatic executable compatibility gate remains open.

compiled-stamp-probe.rkt is an unsuccessful, separate design experiment. It can
read added compiled-submodule metadata without instantiating the parent, but the
assertion that stripping and serializing the submodule yields a canonical original
body hash fails on both versions. The failing probe exits nonzero; its last success
message is unreachable. This proposed normalization is not SDK implementation.

Commands: raco make/raco test on observation-install, captured-submodules,
command-bootstrap and executable-capture; scripts/check.sh; scripts/check-interop.sh.
Racket 9.2 uses the isolated project compiled root. Logs trim trailing whitespace.
No macOS/Windows or full SDK completion claim is made.

The later racket-mcp-compiled-identity-probe.rkt instead treats the embedded value
as producer metadata for the original compiled input, with no post-rewrite hash
equality claim. It passed on 9.2 and 9.3: changed bodies have different identities,
metadata survives serialization, original submodules remain accessible, and
identity inspection does not instantiate the parent. This is a prospective
compiler integration mechanism, not automatic SDK build sealing. A transformation
after stamping would require a new producer identity.
