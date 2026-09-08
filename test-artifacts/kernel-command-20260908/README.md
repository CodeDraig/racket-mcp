# Kernel command startup, 2026-09-08

The production mcp/command module now uses the kernel language. It imports only
the private kernel observer and resolves its SDK/CLI paths relative to its own
module. Invocation loads the SDK observer under kernel observation and transfers
the snapshot plus later declarations into its registry-scoped collector.
Import alone leaves ordinary SDK modules unloaded. The existing main export and
executable main submodule remain available.

A real stdio fixture walks its own running dependency graph. Both command file
execution and racket -l mcp/command must have observed every ordinary dependency;
predefined modules are counted separately. The previous committed command failed
both cases with missing Racket and SDK libraries; the new command passes. The
baseline experiment restored and recompiled the new entry in a finally clause.

The initial 9.3 command suite passed 15 checks. The broader 9.2 suite passed 29,
including kernel scope tests and a process-restart workflow using a copied SDK:
unchanged code resumes, changed SDK code rejects the saved execution, and fresh
execution still works. The 9.2 run uses an isolated compiled root.

Installed-package dependency checks and 44 installed tests passed. All 14 regular
Go probes passed, plus a targeted official Go client probe through the production
command. That extra probe uses a temporary kernel wrapper solely to supply the
command arguments; it is retained with its absolute checkout paths as evidence,
not as a portable application. Installed raco mcp inspect also passed.
Full 9.3 verification passed compilation, 5,950 native checks, all 1,301 core
schema cases, all 86 optional regex cases, and the updated Scribble build. The explicit runtime identity remains required for predefined
modules and code loaded before the scope, including raco's own early libraries.
Automatic native runtime identity and default workflow build sealing remain open.

Commands: raco make/raco test on the command, kernel, and copied-SDK restart
fixtures; sh scripts/check.sh; sh scripts/check-interop.sh; the official Go probe
through the temporary command wrapper; raco setup --check-pkg-deps and installed
raco test; raco mcp inspect. Logs trim trailing whitespace. Linux 9.2/9.3 were
executed; native macOS/Windows verification remains unavailable.
