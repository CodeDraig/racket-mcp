# Compiled declaration identities, 2026-09-08

The private compiled-identity component and installed compiler hook retain a
producer identity in module-language metadata. Compilation runs once in saveable
mode; the digest is computed with an empty retained cell and filled before the
artifact is returned. Non-module expressions retain their compilation mode.
Nested hooks reuse an in-progress cell. Identity lookup reads already declared
modules, without filesystem fallback or handler execution. Original language-info
providers are delegated. Incomplete identities and dropped metadata are errors.

Eight new cases check compiler evaluation count, changed bodies, original child
modules, preserved language info, malformed compiler output, real MCP source and
compiled entry points, undeclared lookup, and file deletion/replacement after
declaration. The final component run passed eight cases on 9.3; the five-file
focused run passed 57 checks on 9.2. All 14 Go interoperability probes passed.
Installed package dependency setup and the same 57 checks passed. Full Racket 9.3
verification passed compilation, 5,939 native checks, 1,301 core schema cases,
86 optional regex cases and Scribble.

The earlier compiled-submodule stamp idea is rejected: stamp-loading probes show
that a lazily loaded submodule can return the new identity after a loaded parent's
.zo has been replaced. Both probes deliberately exit nonzero. Language-info probes
instead show a retained metadata cell before and after serialization. Successful
SDK regression cases test replacement and deletion through real module loading.

Preserved intermediate failures include raw syntax without namespace context,
compile-time visitation output, immediate-only linklets that cannot be serialized,
and a 9.2 fixture whose isolated compiled root ignored its adjacent .zo. The final
fixture explicitly selects that artifact root; it does not relax identity checks.

Commands: raco make/raco test on compiled-identity, observation-install,
captured-submodules, command-bootstrap and executable-capture; scripts/check.sh;
scripts/check-interop.sh. Racket 9.2 uses the project isolated compiled root except
for the explicit adjacent-artifact fixture. Logs trim trailing whitespace.

Compiler metadata is trusted producer data, not a signature. Transformations
after stamping require a new identity. Default workflow dependency-graph sealing,
preloaded dependencies without evidence, and the full release remain unfinished.
