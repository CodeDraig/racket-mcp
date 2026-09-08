# Module-end build capture and execution phases

The private module hook freezes a declared-code capture at module end, preserves
an enclosing loader build, and leaves failed initialization unsealed. Higher-phase
construction is covered at phases 1 and 2 after compiled loading. This component
is not yet connected to default public workflow construction.

The phase regression demonstrated identical captured fingerprints for execution
namespaces at phases 0 and 1. The corrected mcp-executable/3 payload includes the
namespace base phase. Its runner is also checked to execute at each actual phase.
Earlier captured fingerprints require their compatible SDK/runtime build.

Focused compilation and the six test files passed on Linux Racket 9.2 (54 checks)
and 9.3 (58 checks). The count varies because executable-build.rkt checks each
observed dependency, whose set differs between runtime builds.

Commands, from the repository root with the version-specific environment:

```
raco make tests/module-build-context.rkt tests/executable-build-phase.rkt tests/executable-build.rkt tests/declared-code-capture.rkt tests/captured-dynamic-imports.rkt tests/retained-capture.rkt
raco test tests/module-build-context.rkt tests/executable-build-phase.rkt tests/executable-build.rkt tests/declared-code-capture.rkt tests/captured-dynamic-imports.rkt tests/retained-capture.rkt
```

Installed package dependency checks and the same six test files (58 checks) passed
on 9.3. All 14 official Go interoperability probes passed. The added SQLite
process-restart regression passed 14 checks on both versions
and from the installed package. After the module-end limitation was reproduced,
the final boundary and restart pair passed 19 checks on both versions and from
the installed package. Full 9.3 verification passed compilation, 5,985 native
checks, all 1,301 core schema cases, all 86 optional regex cases and Scribble.
That run began before the added restart file and final boundary assertion; the
separate 19-check runs cover those final additions.

The module-end snapshot does not certify successful initialization: another lifted
expression can fail later, and a repeated dynamic-require does not repeat that
failure. Its original loader must return successfully before the caller seals.
The private hook never seals automatically. The final boundary regression checks
that the build remains unsealed after such a later failure.

Additional commands:

```
raco make tests/module-build-context.rkt tests/module-build-context-worker.rkt tests/module-build-context-restart.rkt
raco test tests/module-build-context.rkt tests/module-build-context-restart.rkt
```


Two consecutive `python3 scripts/package.py` builds produced identical source
ZIP hashes (`cmp` passed); the digest is recorded in SHA256SUMS. The final package
contains the final source, tests and ledger. Native macOS and Windows verification
remains unavailable; this entry makes no additional platform claim.

Trailing whitespace was trimmed from the installed setup log for Git checks.
