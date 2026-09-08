# Scenario acceptance closure

The approved scenario requirement promises deterministic adapters, a clock,
principal and input responses, plus cancellation, disconnect, process restart,
conflicting inputs and uncertain effects. It does not require a new scheduler
language or arbitrary automatic fault discovery.

| Required behavior | Inspected evidence |
|---|---|
| Authored form, isolated test submodule, assertion failure reaches CLI | tests/scenario.rkt |
| Local, stdio, HTTP JSON/SSE; clock, principal, adapters, input callbacks | tests/scenario-session.rkt |
| Concurrent request handles and cancellation | tests/scenario-requests.rkt |
| Disconnect, reconnect, no replay, task worker survival | tests/scenario-disconnect.rkt |
| Child process kill/restart and persisted checkpoints | tests/scenario-process.rkt |
| Uncertain effects; transactional/idempotent/manual recovery; explicit boundary synchronization | tests/scenario-effect-crashes.rkt (18 transport/policy/boundary combinations) |
| Conflicting partial input submissions, one winner, retained value, completion | tests/scenario-conflicting-inputs.rkt (new local/stdio/HTTP cases) |

The existing files above were inspected and passed in the ed75ea8 full Linux 9.3
run. Their source has not changed since that run. The new conflicting-input cases
passed all three tests on Linux Racket 9.2 and 9.3. Expected outcomes are authored
in these tests, not generated from the workflow compiler. No scenario runtime
changes were needed. SCENARIOS is removed from REMAINING.md. Remaining task,
embedding and every-boundary durability acceptance belongs to DURABILITY rather
than an unbounded scenario-tooling requirement.
