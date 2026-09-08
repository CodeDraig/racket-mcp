# Client subscription validation

The initial raw stdio/HTTP peer run reproduced 17 failures among 19 cases.
Both partial-acceptance cases passed. The peers kept their transport open; invalid
messages were delivered without settling the request. This first result is in
the task's terminal history, not a separately retained log.

A shared request tracker now validates IDs, acknowledgement order, accepted
subsets, and core/Tasks event filters before notification delivery. The stdio
reader no longer uses params.requestId as a subscription correlation fallback.
Actual sent filters and accepted filters are copied to isolate caller mutation.
The separate ack-mutation-before.log records the reproduced accepted-URI mutation
failure (1/23); the final logs include its regression.

The focused group passed 210 tests. One earlier run encountered a stale compiled
subscription.rkt dependency; explicit raco make fixed it. linux-9.2.log and
linux-9.3.log each contain 1,008 passing selected checks before the final accepted
filter copy. The *-final.log files are the authoritative subsequent runs.

Reproduction from the repository root:

    . scripts/racket-env.sh
    set -- tests/subscription*.rkt tests/stdio*.rkt tests/http*.rkt tests/progress.rkt tests/upstream-subscription.rkt tests/upstream-task-subscription*.rkt tests/upstream-resource-loss.rkt tests/upstream-task-loss.rkt tests/scenario-subscriptions.rkt
    raco make "$@" examples/greeter.rkt
    raco test "$@"

Racket 9.2 uses PLTCOMPILEDROOTS=$PWD/.cache/ci/compiled-9.2-effect.
Racket 9.3 uses .cache/racket-9.3/bin on PATH and
MCP_RACKET_USER_HOME=$PWD/.cache/ci/package-home-9.3-current.

sh scripts/check-interop.sh passed all 14 official Go probes. The manual built
with raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl.
Those runs precede the final accepted-filter copy. Installed checks unset
PLTCOLLECTS, use the 9.3 package home as PLTUSERHOME, run
raco setup --no-docs --check-pkg-deps --pkgs racket-mcp, then run the new validation,
stdio-overflow and subscription tests from .cache/distribution/racket-mcp/tests.

This is focused transport/integration verification, not a new full SDK, schema,
independent conformance or native macOS/Windows run. Terminal subscription result
validation and the complete reconnect/failure matrix remain open. Log trailing
whitespace may be removed for version-control checks; result content is retained.

Final-source Go interoperability passed all 14 probes (go-final.log). Installed
Racket 9.3 dependency setup and 48 selected checks passed (installed-final.log).
The 9.3 final selected source run passed 1,009 checks.
The 9.2 final selected source run also passed 1,009 checks. The final source ZIP
was rebuilt twice and byte-compared; distribution-SHA256SUMS records its digest.
