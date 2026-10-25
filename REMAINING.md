# Remaining release work

Mutable current state for the approved seven-milestone MCP 2026-07-28 release.
Remove a row when its completion evidence or an approved scope change is recorded
in IMPLEMENTATION.md;
replace a partial row with only its unmet portion. Do not reopen completed work
without a regression or a dependency of a remaining requirement. Historical
"remains open" statements in IMPLEMENTATION.md are not additional work items.

Current status: 2026-10-25. No remaining requirements in the approved release
scope. The Tasks error-ordering regression below is an explicitly accepted
known limitation, not an additional publication gate. Repository visibility
remains private; this acceptance does not authorize making it public.

On 2026-09-08, the user removed native macOS/Windows testing from the plan
because no immediate verification route is available. This removes the PLATFORM
requirement; it does not establish support on either platform. Linux Racket
9.2/9.3 is the verified release platform. Native macOS/Windows remain unverified.

The latest full Linux checks, recorded on 2026-10-25, passed on both Racket 9.2
and 9.3: 6,852 native tests, 1,301 schema cases, 86 regex cases, Scribble,
compilation, package dependency validation, all 14 Go interoperability probes,
and 38 selected installed-package checks per version. Fresh bootstrap checks
passed and the two archives built in that run were byte-identical. See
[the validation record](test-artifacts/public-readiness-20261025/README.md).
Its source manifests identify the tested files; subsequent documentation edits
do not imply rebuilt archives or a new runtime validation run.

The original-plan evidence map remains in
`test-artifacts/release-acceptance-20260908`; its historical platform gate is
superseded by the scope change above. Optional format assertions remain outside the approved
annotation-default requirement; regex support follows the tested compatibility
profile. The ordinary build identity is application-declared, as explicitly chosen.

## Accepted Tasks error-ordering limitation

The September 8 dedicated Tasks receipt had 43 successes, one failure and one
skip. The October 25 rerun has 42 successes, two failures and one skip. All 195
recorded harness input file hashes match between runs. The additional failing
check is `sep-2663-tasks-methods-non-declaring`: `tasks/get`, `tasks/update`, and
`tasks/cancel` without the Tasks extension capability and with an unknown task
ID return `-32602`, while the harness requires `-32021` for the missing capability.

Commit `d2d2372` added ownership checks before policy callbacks could receive a
task's saved arguments. Those checks also precede capability validation, so an
unknown task is rejected first. This attribution follows the source diff and
current control flow; no commit-by-commit bisect was run. The documentation and
bootstrap commit `4ab93a8` exposed the discrepancy through validation and did not
change runtime behavior.

On 2026-10-25, the user explicitly accepted this ordering issue for now as a
trade-off while retaining the ownership protection and the workflow replay,
saved-default, and input-validation fixes. The demonstrated impact is an
incorrect diagnostic for a request that is rejected in both versions. No lost
work, unauthorized access, or real-client breakage due to the ordering was
demonstrated. A client that branches on the error code could behave differently;
that consequence remains unverified. The other fixes address valid work failing
to resume and saved arguments reaching policy callbacks before ownership checks.

This is not a permanent incompatibility requirement or proof that security and
conformance conflict. A future fix should check capabilities in the appropriate
place while retaining ownership checks before saved arguments reach policy
callbacks, and verify both HTTP and direct runtime paths. Until then, retain the
failure in reported results rather than weakening the harness expectation.

## Other qualified results

The October 25 core run retains 144 successes, four excluded roots/sampling
fixture failures and one MRTR warning. The dedicated Tasks run retains the
taskId/header disagreement and notification skip alongside the ordering failure.
All twelve client scenario processes exit zero (91 successful checks, four skips).
The corrected-fixture OAuth run has 18 of 20 scenario processes exit zero: six
failed checks remain in `metadata-var2` and the `scope-step-up` warning remains;
`iss-not-advertised` now passes. Real HTTPS offline access passes 12/12 terminal
checks. Fixture corrections do not count as unmodified conformance credit.

Completion of this scope is not an unqualified MCP conformance or SDK-tier claim.
