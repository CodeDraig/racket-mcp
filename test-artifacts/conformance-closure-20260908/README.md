# Qualified conformance closure, 2026-09-08

The pinned harness source/requirements/package hashes match the executed harness.
The SDK source matches the source-sha256.txt recorded for the passing authored
example/Go run. The only subsequent production-tree change is to the development
list-changing fixture: explicitly accept this server's localhost Origin for its
configured positive port. No protocol-runtime source changed.

| Leg | Final evidence | Outcome and qualification |
|---|---|---|
| Core server plus pending header/schema scenarios | ../final-core-fixed-20260908 | 144 SUCCESS, four FAILURE, one WARNING, one INFO outside the Tasks-on-core-fixture results. The four failures require excluded roots/sampling diagnostics. The warning is the recorded interpretation rejecting input responses without a continuation. Localhost Origin and real tool/prompt list changes pass. Harness exit remains 1; no unqualified pass is claimed. |
| Tasks on dedicated fixture | ../final-tasks-forced-20260908 | 43 SUCCESS, one FAILURE, one SKIPPED across ten exact scenarios. The failure expects Mcp-Name=taskId for tasks/get. Pinned core transport specifies Mcp-Name only for tools/call, resources/read and prompts/get; pinned Tasks taskId fields do not add that header annotation. The skip is the harness's unfinished subscriptions/listen notification rewrite. Native task-subscription behavior has separate tests. |
| Applicable core client plus CIMD/pre-registration/resource/issuer checks | ../final-clients-20260908 | 62 SUCCESS, four SKIPPED, no failures/warnings. The skips are excluded roots/sampling and initialize/notifications-initialized, which this revision does not use. All twelve scenario processes exit zero. |
| Offline access/CIMD document | ../final-offline-access-20260908 | Real trusted loopback HTTPS fetch; terminal 12/12 pass, exit zero. The harness writes checks.json before its shutdown-time grant_types check; the later terminal success is retained separately. Optional offline_access omission is INFO. |
| Independent official Go SDK | ../authored-example-docs-20260908/go.log | All 14 probes pass on the same SDK source, including both directions where implemented. No Go Tasks notification capability is inferred. |

The broad requirements runner also invokes ten Tasks scenarios against the core
fixture, producing 15 successes, 27 failures and one skip there. Those are retained
as fixture-inapplicable results and replaced for Tasks acceptance by the dedicated
43/1/1 run. They are not silently counted as successful tests.

The failed first core refresh (localhost Origin configuration), rejected tasks-*
selector, and exact Tasks scenario run without --force (all applicability skips)
are retained in final-core-20260908, final-tasks-20260908 and
final-tasks-fixed-20260908. The forced run is the executable Tasks evidence.
The initial offline metadata generator accidentally selected Racket 9.2 against
9.3 compiled files and failed before any scenario; selecting the 9.3 PATH resolved
that environment mismatch. runner.log records the successful corrected run.

Authorization fixture exclusions retain the precise audit in
../oauth-offline-access-20260908/README.md: complete fixtures requiring DCR are
outside this release, even when they additionally exercise supported discovery,
scope, token, refresh or issuer behavior. Those supported pieces retain native
behavioral evidence. Hosted authorization-server scenarios and other optional
OAuth extensions are excluded as approved.

Recorded subscription interpretation remains: emit the dedicated graceful
completion result; accept it or the cancellation notification on the client.
The Go probes cover the implemented closure behavior. The MRTR warning and Tasks
header discrepancy are reported as interpretations/disagreements, not hidden by
patching the pinned harness or inventing wire behavior.

CONFORMANCE is removed from mutable remaining work with these explicit
qualifications. A later SDK regression or BUILD change affecting these paths
requires the relevant refresh, not repetition of unrelated completed cases.
