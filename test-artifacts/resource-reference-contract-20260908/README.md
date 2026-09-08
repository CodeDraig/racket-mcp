# Resource-reference construction and resolution, 2026-09-08

The direct resource-ref constructor now shares declaration/argument validation
with a resource application: descriptor type, proper argument list, exact arity,
and per-argument schema. Resource applications delegate to this one constructor.
Neither construction path reads a resource.

Dynamic reference resolution now requires exactly one matching declaration
identity in the active interface. Missing targets retain their error; ambiguous
mounts now error instead of silently choosing the first entry. This agrees with
the existing construction-time policy for declared reference maps. It does not
introduce a per-operation mapping for multiple mounts of the same identity or
infer arbitrary references inside separately defined Racket helpers.

The first authored regressions reproduced two failures: direct construction
accepted malformed references and dynamic resolution chose a mount by list order.
The corrected tests cover constructor equivalence, malformed arity/types, both
mount orders, unique URI/name remapping, and target removal. A further local
JSON-RPC dispatch case creates references inside ordinary procedures with no
static reference metadata; both link and embed fail with -32603 before any reader
runs. Focused 9.3 compilation and 70 checks passed, including existing domain,
inferred-reference, and upstream cases. The same 70 checks passed on 9.2 using an
isolated compiled root. Full 9.3 verification passed compilation, 5,957 native checks, all 1,301 core
schema cases, all 86 optional regex cases, and the Scribble build.

All 14 official Go interoperability probes passed. Installed-package dependency
checks and 70 installed tests passed. Commands: raco make/raco test for the four
focused files on both versions, sh scripts/check.sh, sh scripts/check-interop.sh,
python3 scripts/package.py, and raco setup --check-pkg-deps --pkgs racket-mcp.
Native macOS/Windows are unverified. Retained logs trim trailing whitespace.
