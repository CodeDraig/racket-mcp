# Upstream task control races, 2026-09-08

Six authored cases exercise the existing task worker claim with memory storage
and with two separate SQLite connections to the same local database:

- A held poll returns completion while a working observation and cancellation
  have been started. Both see the recorded terminal state, and no cancellation
  reaches the peer. Subsequent reads preserve the terminal revision.
- The local handle expires while that poll holds the claim. Poll, observation
  and cancellation all return -32602; no task revision or upstream mutation is
  added after expiry.
- An upstream cancellation is held while duplicate cancellation and a completion
  observation start. Only one cancellation reaches the peer; the observation
  establishes completion and later reads do not change it.

Each case also checks that a foreign principal is rejected while the worker is
active. Semaphores hold the first peer operation and signal competing request
starts; result channels and persisted revisions check the outcomes. This is one
host with cooperating threads and, for SQLite, separate connections. It is not
distributed execution, process termination, remote TTL translation, subscription
loss/reconnection or exhaustive scheduling coverage.

The new fixture and existing observation, consumed-input and interrupted-mutation
suites passed 75 checks on Racket 9.2 and 9.3. The only failed initial run was an
unbound fixture clock function; it was corrected to manual-clock-advance!. No
production code was changed. The preceding full SDK suite therefore remains the
runtime baseline; it was not repeated for these additional tests.

Commands: raco make and raco test on tests/upstream-task-races.rkt,
tests/upstream-task-observation.rkt, tests/upstream-task-stale-input.rkt and
tests/upstream-task-interruption.rkt, using the project package environments and
an isolated 9.2 compiled root. Logs have trailing whitespace trimmed.
