# Kernel observation handoff, 2026-09-08

The private raw-kernel observer records compiled declarations per module registry.
The SDK observer can import its snapshot and receive subsequent observations from
retained kernel evaluator hooks. Direct declarations take precedence over nested
objects recovered from parent compiled modules. Registry maps use ephemerons.

The first snapshot-only handoff missed racket/private/config.rkt during the cold
greeter dependency walk. Flattening the kernel implementation into the worker and
mutating the evaluator parameter did not fix it. Loading the application before
transfer did pass. Forwarding later kernel observations into the SDK collector
also passes while keeping application loading after transfer. This is evidence
for the handoff behavior, not a proof about every Racket resolver implementation.

The initial focused checks passed 26 cases on Linux Racket 9.2 and 9.3.
After the lifetime fix, focused compilation and 27 checks passed on both versions:
kernel-observation, observation-install, and command-bootstrap. The 9.2 run used
an isolated compiled root. The command module was explicitly rebuilt because the
initial run retained an importer compiled against the old private function ABI.

Cases include separate registries with identical module names, exact recorded
code replay, one-shot transfer, hook restoration on exceptions, malformed seeds,
retained hook delivery during the SDK scope, no delivery after that scope exits,
and a child-process dependency walk requiring evidence for every ordinary module.

A further regression reproduced an abandoned scope retaining a usable transfer
function. Kernel scope exit now clears records and the forwarding receiver and
rejects subsequent transfer or continuation re-entry. Retained hooks delegate
unchanged after closure. SDK receiver shutdown is synchronized with delivery;
malformed initial snapshots cannot consume a handoff. The failure is retained in
lifetime-before.log.

The first full 9.3 run was deliberately stopped with SIGTERM to apply this fix;
it is not a test failure or a passing full run. The fresh full 9.3 run passed
compilation, 5,947 native checks, all 1,301 core schema cases, all 86 optional regex
cases and the Scribble build. Focused 9.2 verification passed 27 checks.
This private worker
does not replace the serving entry point, identify the native runtime image, or
create and seal default workflow build contexts. Production startup integration remains pending.

All 14 official Go probes passed. Installed-package dependency checks and 54
installed tests passed, including capture and loader cases. A temporary raw-kernel
command entry ran inspect successfully on both Racket versions. Its source uses
an absolute checkout path and is retained only as a development experiment; it
is not a portable launcher or an installed production command.

Commands: raco make/raco test for the three focused files on both versions;
sh scripts/check.sh; sh scripts/check-interop.sh; python3 scripts/package.py;
raco setup --check-pkg-deps --pkgs racket-mcp and five installed test files.
Retained logs trim trailing whitespace. No native macOS/Windows result is claimed.
