# Durable transition audit, 2026-09-08

This audit follows the approved persistence requirements. It does not expand them
into arbitrary instructions or SQLite implementation internals. Compiler build
capture remains a separate BUILD requirement.

| Transition | Existing evidence / new missing-boundary probe |
|---|---|
| Initial instance/key creation; arguments and owner association | workflow.rkt; task-keys.rkt; task-key-restart.rkt; scenario-effect-crashes.rkt. Fresh unkeyed calls differ, concurrent keyed calls share work, different arguments fail. |
| Branch selection and checkpoint value commit | branches.rkt and workflow-match-restart.rkt retain decisions across suspension/restart. New mcp-persistence-boundaries.rkt kills before branch commit, after branch commit, before checkpoint commit and after checkpoint commit. Direct SQLite assertions distinguish committed from unfinished computations. |
| Input request preparation and persistence | input-stage-lock.rkt verifies host computation releases the database and cancellation wins before commit. New process probe kills during preparation and after the pending request is persisted. |
| Partial grouped responses, final input advancement | input-groups.rkt and scenario-conflicting-inputs.rkt cover validation, retained partial responses, decline/cancel, conflicts and concurrent fresh IDs locally/stdio/HTTP. New process probe kills after partial acceptance and after final input advancement. |
| External effect intent, mutation, result commit | scenario-effect-crashes.rkt: 18 process-kill combinations, stdio/HTTP x transactional/idempotent/manual x before/after/recorded. restart.rkt, effect-input-lock.rkt and recovery-races.rkt cover uncertainty and active recovery exclusion. Do not repeat this matrix. |
| Completion and retained terminal result | New process probe kills before completion commit and after the terminal result is stored; two fresh process resumes return the recorded outcome. Existing workflow.rkt covers continuation receipt replay. |
| Task creation/handoff, worker launch and input update | task-boundary-restart.rkt, task-key-restart.rkt, task-restart.rkt: persisted handles and state survive processes, active worker exclusion, reauthorization. tasks.rkt checks update during worker-claim release, avoiding lost wakeups. |
| Task cancellation and terminal immutability | checkpoint-lock.rkt and input-stage-lock.rkt inspect cancelled stages for absence of committed values; tasks.rkt and task-keys.rkt preserve completed/failed outcomes against cancellation and retries. |
| Manual repair and replacement task | recovery-codec-lock.rkt, recovery-races.rkt, task-recovery.rkt and task-recovery-process.rkt. Process kills before replacement, after queueing, during effect and after completion preserve immutable old handles and journaled replacement receipts. |
| Parent rendering layout, child request/result, parent child-state commit | embedded-workflows.rkt and render-provenance-restart.rkt retain order, namespaces, provenance and child results. New mcp-render-boundaries.rkt kills after child input persistence but before parent receipt, after child completion but before parent receipt, and after parent receipt before next child. Child checkpoints execute once and terminal render retries do not resolve children again. |
| Handle ownership, expiry, code identity | workflow.rkt, clock.rkt, task-keys.rkt, task-recovery.rkt, view-adapters.rkt and loader-cli-restart.rkt cover foreign owners, clock expiry, changed keyed arguments, workflow version/fingerprint and adapter identity mismatch. Automatic default executable capture is still BUILD, not closed here. |
| Committed changes/outbox | workflow-freshness.rkt, task-freshness.rkt, external-change-restart.rkt and shared-resource-freshness.rkt already demonstrate commit/rollback ordering, retryable publication and owner partitioning. CACHE is completed and is not reopened. |

New probes use ordinary documented stage constructors and real SQLite files.
They kill a separate process at a callback or returned-outcome boundary, inspect
persisted state independently, then resume in two new processes. They do not
modify the SDK, insert storage hooks, or interpret an uncommitted computation as
exactly-once. The eleven test cases pass on Linux Racket 9.2 and 9.3, both as temporary
probes and after repository integration. The integrated logs include the nine
new grammar cases as well: 20 passing cases on each version. The 9.3 run also
builds the updated manual. Both integrated processes exited zero.
