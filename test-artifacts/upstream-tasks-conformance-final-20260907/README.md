# Bridged Tasks conformance, 2026-09-07

The pinned independent MCP conformance harness targeted
`dev/conformance-upstream-tasks.rkt`: HTTP local bridge, native stdio upstream,
separate ephemeral stores and principals. The bridge used the ordinary public
adapter/runtime APIs and the existing Tasks fixture. All 191 harness source files
in the executed working copy matched the vendored sources by SHA-256.

Final results across ten explicitly forced Tasks scenarios: **43 SUCCESS,
1 FAILURE, 1 SKIPPED**. This is partial conformance evidence, not a passing release.

- Passing scenarios: lifecycle, capability negotiation, wire fields,
  request-state removal, MRTR input, dispatch/envelopes, required-task capability
  error, and MRTR-before-task composition.
- Header scenario: retains the previously documented disagreement over mandatory
  `Mcp-Name` mapping for `tasks/get`. No undocumented header was added to satisfy it.
- Notification scenario: skips itself because this pinned harness does not yet
  listen on `subscriptions/listen`. It provides no task-notification evidence.

The first run is retained in `../upstream-tasks-conformance-20260907`. It exposed
an actual bridge defect: upstream `-32021` was converted to `-32603`. The corrected
bridge preserves the capability code/data; the final independent scenario passes.

Reproduce the fixture:

```sh
. scripts/racket-env.sh
raco make dev/conformance-upstream-tasks.rkt
racket dev/conformance-upstream-tasks.rkt
```

Use its printed endpoint with the pinned harness working copy:

```sh
node_modules/.bin/tsx src/index.ts server --url <printed-url> \
  --scenario tasks-lifecycle --spec-version 2026-07-28 --force \
  --output-dir <results-directory> --timeout 60000
```

Repeat for each scenario named by the `.log` files in this directory. Raw
`checks.json` files retain individual assertions and their results. The fixture
was stopped after the run. Verification platform: Linux x86_64, Racket 9.2.

The pinned official Go SDK's `NotificationSubscriptions` has no Tasks filter and
no native task-notification handler. Existing Go probes remain evidence for core
and resource interactions; they are not counted as Tasks interoperability.

Native regression validation initially reported three HTTP child-startup errors
in the effect crash suite (`native-initial.log`). Without source or deadline
changes, the isolated crash/process rerun passed 54 checks (`startup-recheck.log`),
and the final full native run passed 4,928 (`native-final.log`). The startup
failures did not reproduce; their cause remains undiagnosed. Separate schema,
documentation, package and thirteen Go regression probes passed.
