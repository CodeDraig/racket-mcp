# Actual list mutation conformance

The new diagnostic application selects immutable interface snapshots and shares
one subscription hub. Each trigger toggles a real tool or prompt entry before
publishing the corresponding event. It uses the ordinary HTTP handler and runtime;
no SDK dispatch or upstream harness behavior changed.

The native regression verifies absent -> present -> absent list entries and the
acknowledged events on HTTP, preserving the original entries. It passed on Linux
Racket 9.2 and 9.3. The initial test incorrectly read the raw JSON-RPC envelope as
a result and failed; linux-9.2-fixed.log supersedes that test-authoring failure.

The pinned independent server-stateless scenario exited zero with 30 success,
zero failures, zero warnings. Both list-change checks now pass. See commands.json,
exit.json, run.py, harness-inputs.json and raw results. Other conformance scenarios
were not rerun for this development-fixture-only change.
