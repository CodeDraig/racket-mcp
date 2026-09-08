# Early SDK module observation, 2026-09-07

Platform: Linux x86_64, Racket 9.3. The command entry observes SDK module code
before loading the CLI. Captured interface loading uses observed bootstrap code
from the SDK's original module registry; unobserved bootstrap modules still use
the caller's explicit runtime identity. Default/direct loading is not completed.

The initial restart fixture compiled SDK sources separately in fresh processes.
An unchanged-source restart rejected saved execution. Temporary-copy diagnostics
isolated a changed compiled-code digest in `mcp/schema.rkt`; the failure and
diagnostic outputs are retained. No runtime source-file hashing was substituted
for actual executable evidence. The final regression builds one SDK before
restarting it, then changes and rebuilds the SDK before checking rejection. The
manual documents this executable-build distinction. A preliminary fixture error
passed a non-simple path to `find-relative-path`; that test path was corrected.

The focused compiled-build regression passed six checks before adding three
fresh-execution assertions. Registry observation passed eleven checks, covering
changed files, distinct namespaces, and independent observation lifetimes.
The final full native run contains the expanded nine-check restart regression.

Reproduce using the project-local Racket 9.3 installation:

```sh
env PATH="$PWD/.cache/racket-9.3/bin:$PATH" \
  MCP_RACKET_USER_HOME="$PWD/.cache/ci/package-home-9.3-current" \
  sh scripts/check.sh
```

The final full run passed 4,962 native checks, 1,301 core schema cases and
Scribble. All 13 Go probes, distribution construction, installed package dependency
checks and installed-command inspection also passed. Setup-log trailing
whitespace was trimmed when saving `package.log`. These tests do not establish automatic provenance for
preloaded runtime modules or macOS/Windows behavior.

The focused registry observer also passed 11 checks under Linux Racket 9.2,
loading source with `use-compiled-file-paths` set to `null` to avoid consuming the
workspace's 9.3 bytecode. This is a focused check, not a new full 9.2 SDK run.
