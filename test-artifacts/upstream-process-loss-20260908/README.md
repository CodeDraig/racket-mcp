# Upstream acceptance closure

New mcp-upstream-process-loss.rkt runs a real HTTP Racket Tasks server in a
separate process and kills the local bridge after the peer acknowledges a task
update or cancellation, before the bridge records that acknowledgement. SQLite
inspection confirms an outstanding command intent. Two fresh bridge processes
report the same failed recovery-required task. HTTP-boundary request counts prove
one creation and one control request, with no automatic replay.

Both repository test cases pass on Linux Racket 9.2 and 9.3, exit zero. The initial
probe counted runtime authorization callbacks, which also run during background
task resumption, and falsely counted a repeated tools/call. Its failed log is
retained. The corrected probe counts incoming Mcp-Method headers in the HTTP
authentication adapter; no SDK behavior changed to make this pass.

The rest of the UPSTREAM row maps to unchanged tests included in the 6,238-test
full 9.3 run recorded in ../authored-example-docs-20260908:

- upstream.rkt: actual SDK peer snapshot and invocation, schema/discovery changes
  rejected before invocation, immutable pins, transformed domain outputs,
  completion and explicit inverse URI adapters.
- upstream-task-restart.rkt: persisted local/upstream IDs and namespaced inputs
  survive multiple process generations, with one original remote invocation.
- upstream-task-races.rkt: queued poll/cancel/observation serialization, foreign
  owner rejection and expiry while waiting on another owner of the worker claim.
- upstream-task-observation.rkt: capability/credential/authorization checks,
  validated mapped results, duplicate suppression, terminal immutability, and
  observations cannot resolve uncertain command intents by inference.
- upstream-task-subscription.rkt: real SDK peer over local/stdio/HTTP, notification
  completion without polling, input/URI/handle mapping, re-subscription and
  credential revocation.
- upstream-task-subscription-filters.rkt and upstream-task-loss.rkt: malformed or
  unaccepted events, expiry before connection, loss/graceful/cancel closure,
  affected-subscription isolation and unchanged durable task state.
- upstream-task-stale-input.rkt, upstream-task-interruption.rkt,
  upstream-task-repair.rkt and upstream-task-retry.rkt: stale input identities,
  uncertain updates, explicit repair/retry decisions and immutable old receipts.
- upstream-bridge-restart.rkt and upstream-bridge-recovery.rkt: MRTR translation,
  uncertain initial requests, ownership and explicit repair.

UPSTREAM is removed. Final conformance and native platform verification remain
separate gates; no independent Go Tasks support is inferred from its core probes.
