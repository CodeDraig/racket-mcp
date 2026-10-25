# Public-readiness documentation and validation — 2026-10-25

The README now installs the pinned dependency and SDK before running examples.
Thirteen workstation-local report links now point to the inspected source at
commit `b72e8c3b6e24422267e9e7f522a11cfd8807aead` on GitHub.

Fresh validation exposed one additional bootstrap defect: installing the SDK
with `--no-setup` does not register `raco mcp`. The README and CI bootstrap now
run `raco setup --no-zo --no-docs --pkgs racket-mcp` before CLI use. SDK runtime
and test sources were not changed.

## Source and environment

- Base commit: `b72e8c3b6e24422267e9e7f522a11cfd8807aead`.
- Tested changes: `README.md`, the two files under `reports/`, and `scripts/ci.py`.
- Linux x86_64, Racket CS 9.2 and 9.3. See [environment.json](environment.json)
  and each run's `racket-version.log` for tool versions.
- Each version used a fresh source copy and two empty package homes: one for
  the README bootstrap and another for CI's independent bootstrap. Existing
  checkout caches and the untracked `research_notes/` files were preserved.
- The two passing source manifests are identical. All 3,626 recorded tracked
  files also matched the working tree after validation. See
  [final-checks.json](final-checks.json) and the per-run `source-sha256.json` files.
- Racket 9.2 was installed only below `.cache/public-readiness-20261025/tools`.
  [Download provenance](racket-9.2-download.json) records the official URL and
  verified published SHA-256; [installation output](racket-9.2-install.log)
  records the local destination. Setup retrieval retries are in `environment.json`.
- Go source-archive builds used process-local `GOFLAGS=-buildvcs=false`; the
  isolated source copies deliberately have no `.git` directory.

## Passing native and distribution checks

| Check | Racket 9.2 | Racket 9.3 |
| --- | --- | --- |
| README bootstrap, registration, greeter compile and EOF shutdown | Pass | Pass |
| Independent CI bootstrap and full compilation | Pass | Pass |
| `raco test tests` | 6,852 passed | 6,852 passed |
| Pinned JSON Schema suite | 1,301 passed | 1,301 passed |
| Regex suite | 86 passed | 86 passed |
| Scribble manual | Pass | Pass |
| Installed package dependency validation | Pass | Pass |
| Official Go interoperability commands | 14 passed | 14 passed |
| Selected installed-package checks | 38 passed | 38 passed |

Terminal step statuses and exact commands are in
[racket-9.2/report.json](racket-9.2/report.json) and
[racket-9.3-corrected/report.json](racket-9.3-corrected/report.json).
Their `native-ci/` directories contain the CI runner's reports and command logs.
The installed checks cover `declared-build`, `declared-build-cli`, `cli-artifacts`,
and `view-adapters`, with no `PLTCOLLECTS` override.

Two independent source archive builds are byte-identical and pass ZIP integrity
checks: 1,641 files, 4,544,622 bytes, SHA-256
`9821f8c277a89f721de33e105c71a2302996ee63fea98a48fe738fa5d55fd349`.
See [reproducibility.json](reproducibility.json). Archives remain in the isolated
work directories under `.cache/public-readiness-20261025/`.

## Retained failed first native run

[racket-9.3/](racket-9.3/) is the complete first attempt, before the registration
correction. Its full native command exited 1 with `2/6817 test failures`:
`command-observation.rkt` received no JSON from the unregistered command, and
`loader-cli-restart.rkt` reported `Unrecognized command: mcp`.

[registration-before.log](registration-before.log) reproduces the missing
command directly. After the setup step, an installed `raco mcp inspect` exits
zero; see [registration-after.json](registration-after.json). Both complete
version runs subsequently passed. The first attempt is not counted as a pass.

## Conformance results remain qualified

The pinned harness is commit `7022d786071e6d868dcd5cf19a8c30db7d811537`.
Core, Tasks, client and offline-access runs use its unchanged source. OAuth
registration scenarios use the existing, explicitly corrected fixture from
`scripts/prepare-conformance.py`; the patch and hashes are retained under
[conformance-retry/](conformance-retry/). These are Linux/Racket 9.3 runs.

| Leg | Result | Qualification |
| --- | --- | --- |
| Core, excluding Tasks against the core fixture | 144 success, 4 failure, 1 warning, 1 info | Same roots/sampling exclusions and MRTR warning as the September record; harness exits 1. |
| Tasks swept against the core fixture | 14 success, 28 failure, 1 skip | Retained separately; not used as dedicated Tasks acceptance. |
| Dedicated Tasks | 42 success, 2 failure, 1 skip | Existing taskId/header disagreement and notification skip, plus the capability/error-ordering failure below. |
| Twelve client scenarios | All processes exit 0; 91 success, 4 skip, 42 info in raw checks | Skips remain explicit. |
| Twenty corrected-fixture OAuth scenarios | 18 processes exit 0; 290 success, 6 failure, 1 warning, 341 info | `metadata-var2` has the existing six failures; `scope-step-up` retains the scope-union warning. The previously failing `iss-not-advertised` scenario now passes. |
| Real loopback HTTPS offline access | Terminal 12/12 pass, exit 0 | `checks.json` is written before the final shutdown-time grant-types check; the terminal log contains that twelfth success. |

See [conformance-retry/summary.json](conformance-retry/summary.json), per-leg
command/exit files, and logs. Every failed, warned, or skipped check is retained
in the summary. Full raw checks stay in
`.cache/public-readiness-20261025/conformance-retry/`; their hashes are recorded
in each leg's `checks-sha256.json`. Driver exit zero is not a conformance pass.

### Additional failure relative to the historical Tasks baseline

`sep-2663-tasks-methods-non-declaring` fails on all three operations:
`tasks/get`, `tasks/update`, and `tasks/cancel`. The harness supplies the unknown
task ID `gate-test` without negotiating the Tasks extension. It expects `-32021`
(missing required capability); the current SDK returns `-32602` (unknown/foreign
task). This check previously passed in the September dedicated Tasks receipt.
It also appears in the Tasks sweep against the core fixture.

The current HTTP and runtime paths check task ownership before later dispatch:
see `mcp/private/http-server.rkt:146`, `mcp/runtime.rkt:91`, and
`mcp/private/runtime-policy.rkt:99`. The harness case is in
`vendor/conformance/src/scenarios/server/tasks/capability.ts:128`.
This behavior already exists in the tested base runtime; no runtime or harness
expectation was changed by this documentation/bootstrap patch. The next sharp
edge is to resolve capability-versus-ownership validation ordering while
preserving the unknown/foreign-task access boundary. No unqualified conformance
or public-release clearance is claimed here.

## Harness startup retries

[conformance/](conformance/) retains the failed initial harness attempt, which
produced no scenario checks. Its 112-byte `tsx` IPC socket pathname exceeded the
Unix-domain pathname limit, and the old corrected OAuth harness's dependency
symlink pointed to a removed temporary directory. The retry uses the short
`.cache/cf-public-20261025` scratch path and a newly prepared corrected fixture
linked to the existing working development dependencies. No global installation,
TLS bypass, SDK change, or harness expectation change was used to resolve these
startup failures. The rerun driver rejects legs that produce no `checks.json`.

## Reproduction

`run.py` copies Git-tracked source into a new work directory, executes the README
bootstrap, then runs the existing `scripts/ci.py`, `scripts/check-interop.sh`, and
selected installed checks. It refuses to overwrite existing work/result paths.
Use fresh path suffixes when repeating:

```sh
python3 test-artifacts/public-readiness-20261025/run.py \
  --version 9.3 --racket-bin "$PWD/.cache/racket-9.3/bin" \
  --work .cache/public-readiness-repeat/racket-9.3 \
  --results test-artifacts/public-readiness-repeat/racket-9.3
```

Use the recorded 9.2 binary directory and another fresh work/result pair for 9.2.
`conformance.py` reuses the recorded historical scenario runners with explicit
work/output paths; it requires the pinned development harness dependencies and
the corrected fixture prepared at the path declared in that script. Every
executed adapted runner is retained beside its logs.

Native macOS/Windows and hosted Actions were not run. Repository visibility and
workflow enablement were not changed. The requested delivery remains private.

The final staged whitespace check reports trailing whitespace in retained raw
Racket logs and copied fixture patch context. Those evidence bytes are preserved;
the edited source, documentation, and validation runner files pass the same check.
