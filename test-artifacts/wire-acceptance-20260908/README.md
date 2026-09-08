# Wire acceptance audit

The WIRE row is closed against the approved concrete cases below. This is native
Linux acceptance, not a claim that every possible schedule has been enumerated.
The final independent conformance and native platform gates remain separate.

| Required case | Inspected implementation tests / independent evidence |
|---|---|
| Strict request envelopes, IDs, invalid notifications cannot cancel workers | tests/request-envelopes.rkt |
| Strict response envelopes, response correlation, discriminator and per-request capability checks | tests/wire-messages.rkt |
| Unsupported versions, absent protocol metadata, no initialization/session/GET stream, origin validation | reader-conformance-refresh-20260908/results/server-server-stateless-*/checks.json; conformance-list-changes-20260908/results/*/checks.json |
| Header/body mismatches and Unicode decoding | tests/headers.rkt, tests/http.rkt; reader-conformance-refresh-20260908/results/server-http-header-validation-*/checks.json and server-http-custom-header-server-validation-*/checks.json |
| Exact bounded UTF-8 JSON and partial codepoints | tests/json-decoding.rkt |
| Incomplete/conflicting HTTP framing, incremental large chunks and bounded headers | tests/http-wire.rkt |
| JSON/SSE responses, keepalives, interrupted streams, foreign/nonincreasing progress | tests/http.rkt, tests/http-streams.rkt |
| Independent requests/IDs, progress routing, owned/borrowed ports, EOF and blocked writers | tests/stdio-lifecycle.rkt, tests/scenario-requests.rkt |
| Client/server cancellation direction, repeated and late terminal outcomes, reserved progress tokens | tests/stdio-cancellation.rkt |
| Output failure stops reader and request workers without waiting for EOF | tests/stdio-output-failure.rkt |
| Cancellation versus completion, schema publication atomicity, header/total deadlines | tests/http-lifecycle.rkt, tests/http-adaptive.rkt, tests/stdio-timeouts.rkt |
| Subscription ack order, accepted filters, IDs, invalid/early terminal results, multiple subscriptions | tests/subscription-client-validation.rkt, tests/subscription.rkt |
| Slow/failed/killed acknowledgement; queue overflow isolates affected listener | tests/subscription-concurrency.rkt, tests/stdio-overflow.rkt |
| Graceful closure versus transport loss, reconnect requires fresh listener, tasks survive disconnect | tests/scenario-disconnect.rkt, tests/scenario-subscriptions.rkt |
| Core capability derivation from installed handlers/storage and removal by views | tests/discovery-capabilities.rkt |
| Subscription policy is rechecked, including HTTP scopes | tests/subscription-policy.rkt, tests/subscription-http-scopes.rkt |

These test files are unchanged from the passing ed75ea8 full Linux Racket 9.3
run (6,199 native cases). The stateless diagnostic refresh subsequently passed
30/30, including actual tool/prompt list mutations. No new transport tests or SDK
changes were needed to close this audit. Upstream facility compatibility remains
under UPSTREAM; the documented subscription shutdown interpretation remains under
CONFORMANCE. Neither is silently waived by this mapping.
