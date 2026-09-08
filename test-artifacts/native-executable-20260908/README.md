# Running executable evidence, 2026-09-08

Captured fingerprints use mcp-executable/2 and include Linux running-executable
SHA-256 evidence when procfs can provide it. The private query is lazy and cached
per module instance. It never substitutes the executable's original pathname.
Filesystem access failures produce unavailable evidence; other failures propagate.
Shared libraries and host-injected libraries are outside this component, so the
existing explicit runtime distribution identity remains required. Other operating
systems currently return unavailable evidence. This is not complete automatic
runtime provenance or default workflow build sealing.

The executable replacement fixture starts a copied Racket, waits for readiness,
replaces its pathname, then makes its first identity query. The original process
must report the old image digest, and a new process must report the replacement.
Both use the same compiled root and explicit runtime ID; their sealed fingerprints
must differ. Removing the image field reproduced equal fingerprints. That retained
run also contains an unrelated guard-construction fixture error, corrected before
the final passing suite. The missing-image-field mutation was restored and rebuilt.

The first Racket fixture used relative collection paths incorrectly; it now anchors
those paths to the original running executable. A later attempt on the workspace
temporary filesystem produced ESTALE from /proc/self/exe after unlink. This real
limitation is retained in workspace-filesystem-stale.log. The replacement test
uses /tmp, where the actual running-image probe succeeds. Unreadable-image behavior
has a separate security-guard regression. Child processes, ports and watcher
threads are owned and cleaned up by the fixture.

Focused compilation and 48 checks passed on Linux Racket 9.3. The broader 9.2
suite passed 71 checks, including loader and retained-capture regressions. Full
9.3 verification passed compilation, 5,953 native checks, all 1,301 core schema
cases, all 86 optional regex cases, and the updated Scribble build. Fingerprint format 1
is conservatively incompatible and requires its original compatible SDK/runtime
for resume. No native macOS/Windows verification is claimed.

All 14 official Go probes passed. Installed-package dependency checks and 75
installed tests passed. Commands include
raco make/raco test for the native-image and capture/loader files,
sh scripts/check.sh, sh scripts/check-interop.sh, python3 scripts/package.py,
and raco setup --check-pkg-deps --pkgs racket-mcp. Logs trim trailing whitespace.
