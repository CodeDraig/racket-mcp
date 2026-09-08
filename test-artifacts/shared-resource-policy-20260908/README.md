# Cache and shared-resource policy acceptance

The documented policy retains private zero-TTL list pages and owner/authority
partitioned resource caches. Shared records use explicit per-owner change outbox
entries, atomically recorded with the mutation. The SDK does not infer an external
sharing relation. This uses existing public APIs; no runtime behavior changed.

Existing inspected coverage (unchanged since the passing ed75ea8 full run):
- tests/pagination.rkt: snapshot cursors, retries, expiry, capacity, foreign owner,
  changed authority/capability/method and zero-TTL private fields.
- tests/resource-cache.rkt: authority separation, parent/child TTL, transitive
  authorization, context changes, expiry, concurrent load invalidation.
- tests/freshness-runtime.rkt: failed/unacknowledged mutations do not publish,
  outbox rollback, owner isolation and authorization recheck.
- tests/workflow-freshness.rkt and tests/task-freshness.rkt: committed stage and
  terminal changes, retained outcomes and publication behavior (see full log).
- tests/external-change-restart.rkt: persisted external feed reconciliation.

The new tests/shared-resource-freshness.rkt passes on Linux Racket 9.2 and 9.3.
It uses a real SQLite application table and three owner partitions. Rollback
keeps old cached values and publishes nothing. Committed fanout refreshes two
owners independently and invalidates a revoked owner's entry without notifying
that owner. Restoring access cannot revive its old cached body. The updated
Scribble manual builds. CACHE is removed from the remaining table. General durable
failure-boundary verification remains under DURABILITY.
