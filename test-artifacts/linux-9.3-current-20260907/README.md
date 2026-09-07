# Current-source Linux/Racket 9.3 verification

Verified the SDK runtime at `09113ad6a9d69e05d220421fda779be18a5b63b9` with the
validation-script corrections in this commit. Platform and commands are recorded
in `final/report.json`. Racket: 9.3 CS; Linux x86_64.
Trailing whitespace emitted by `raco setup` was removed from saved setup logs.

- Fresh project-local syntax-spec and SDK installation succeeded. Initial
  bootstrap logs and the initial report are retained in `initial/`.
- Initial native testing failed in the process scenario. A direct launch of its
  development fixture reported 9.2 bytecode under a 9.3 runtime; the observation
  is retained in `initial/direct-fixture-observation.json`.
- The portable and shell validation scripts now compile every top-level `dev`
  Racket module. The previously omitted subscription fixture is included. No
  startup, acknowledgement or request deadline was increased.
- Corrected compilation and **4,928 native checks** passed, including the failed
  process-scenario suite. All **1,301 core schema cases**, Scribble, distribution
  construction and installed-package dependency checks passed.
- All **13 official Go probes** passed with Racket 9.3 using the freshly installed
  project-local package home (`go-probes.log`).

The bootstrap home was `.cache/ci/package-home-9.3-current`. Initial invocation:

```sh
env PATH="$PWD/.cache/racket-9.3/bin:$PATH" python3 scripts/ci.py \
  --package-home .cache/ci/package-home-9.3-current
```

After correcting the fixture compile list, reran with `--skip-bootstrap` and the
same home. Go probes used:

```sh
env PATH="$PWD/.cache/racket-9.3/bin:$PATH" \
  MCP_RACKET_USER_HOME="$PWD/.cache/ci/package-home-9.3-current" \
  sh scripts/check-interop.sh
```

These are Linux results. macOS/Windows verification, remaining conformance
discrepancies and the rest of the SDK implementation remain release gates.
