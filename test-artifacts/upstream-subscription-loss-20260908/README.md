# Upstream subscription termination, 2026-09-08

Acknowledged resource and task feed termination propagates to matching local
listeners for the same principal. Accepted resource filters use mounted identities;
accepted task filters use stored local IDs. Empty filters affect nothing. Loss
returns -32000 with refresh/re-listen guidance; explicit stop and graceful closure
complete listeners. Resource caches invalidate without fabricated mutation events;
task states and revisions remain unchanged. Applications owning listener recovery
can opt out with #:propagate-loss? #f. No automatic reconnect or replay is added.

The new resource and task suites passed 25 cases through local, stdio and HTTP
sessions. Upstream failures there are injected request outcomes, not real socket
failures. The resource cases verify another principal's listener/cache remain
unchanged, unrelated filters stay open, and interrupted dependency calculation
runs only once. Unknown dependency coverage conservatively closes resource
listeners for that principal; the worker cleanup deadline bounds the callback.

The broader eight-file suite passed 354 checks on Racket 9.2. Installed Racket 9.3
package dependency setup and four installed suites passed 62 checks. All 14 official
Go probes passed after updating the fixture to create fresh downstream listeners
when restarting forwarding scopes. The two Go-server resource probes were then
extended and passed again: each kills the actual server after acknowledgement and
checks local error propagation, over both upstream stdio and HTTP. Both extended
probes also passed on Racket 9.2. A byte comparison confirmed that all 573 SDK,
documentation and test files match the verified installed distribution.

Preserved intermediate failures: the new stalled-callback fixture had one extra
closing parenthesis; the original Go fixture reused a listener after explicit
scope cancellation and timed out waiting for its next change. The corrected Go
fixture asserts completion and recreates the listener, rather than opting out of
the new default. Other older protocol-focused native fixtures explicitly opt out
because they own their downstream lifetimes; the new cases cover the default.

Commands: raco make/raco test for the focused files, scripts/check.sh,
scripts/check-interop.sh, direct dev/resource-subscription-client.rkt stdio and HTTP
runs, scripts/package.py, and raco setup --check-pkg-deps --pkgs racket-mcp.
Racket 9.2 used an isolated compiled root; Racket 9.3 used the project package home.
Logs trim trailing whitespace. Full Racket 9.3 validation passed compilation,
5,921 native checks, 1,301 core schema cases, 86 optional regex cases and Scribble.

This evidence is Linux-native. It does not prove every upstream task/process-loss
interleaving, macOS/Windows support, or completion of the full SDK release.
