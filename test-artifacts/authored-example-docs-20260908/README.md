# Authored example documentation and ordinary SDK reference

Scenario declarations now contribute source-only example records to a separate
manifest-examples export. The docs command includes them without instantiating
application code or running assertions, adapters, configuration expressions or
processes. Older manifests return an empty example list. Examples are distinct
from interface declarations and do not affect interface identity/diff checks.
The manual also documents ordinary descriptors, constructors, request contexts,
results and local dispatch contracts.

Terminal verification:

- linux-9.2-rebuilt.log: 160 passing checks after explicit recompilation.
- cli-linux-9.2.log: 14 passing CLI artifact checks.
- linux-9.3.log: the combined 174 checks pass.
- full-linux-9.3.log: scripts/check.sh exits zero, 6,238 native tests,
  1,301 schema core cases, 86 regex cases and Scribble.
- go.log: scripts/check-interop.sh exits zero; all 14 official Go probes pass.
- installed.log: raco setup --no-docs --check-pkg-deps --pkgs racket-mcp
  and six installed-package test modules exit zero, 157 checks pass.
- docs.log: the initial expanded manual builds successfully. A later wording-only
  correction is built in ../durability-boundaries-20260908/integrated-9.3.log.

The initial malformed test source and stale compiled renderer mismatch are
retained in linux-9.2.log and linux-9.2-fixed.log. Explicitly rebuilding the
selected modules resolved the latter. Neither failed run is counted as passing.
source.patch is a whitespace-normalized preview of tracked compiler/docs changes
before the broad run, not an apply-ready patch; it does
not contain then-untracked tests. source-sha256.txt records the final source set,
including those tests and the subsequently integrated 20 language/durability
checks. Those 20 have separate 9.2/9.3 terminal logs; the 6,238 count predates them.

No complete release or native macOS/Windows success is claimed. Log trailing
whitespace is normalized solely for repository whitespace checks.
