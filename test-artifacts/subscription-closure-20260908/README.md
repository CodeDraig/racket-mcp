# Subscription completion validation

before.log records 9/39 failures with the old implementation. Successful closure
was accepted without acknowledgement, with missing/wrong subscription metadata,
or as input_required. Native stdio, HTTP SSE and HTTP JSON peers exercise the
actual client APIs. Successful complete/default-type results and establishment
errors are positive controls. Existing cancellation tests remain in the group.

The shared subscription tracker now checks successful terminal results in both
clients, after envelope/capability validation and before completion. Errors may
reject establishment without an acknowledgement. Server cancellation retains
its separate compatibility path.

Both Linux Racket 9.2 and 9.3 passed 1,025 selected checks. Reproduction:

    . scripts/racket-env.sh
    set -- tests/subscription*.rkt tests/stdio*.rkt tests/http*.rkt tests/progress.rkt tests/upstream-subscription.rkt tests/upstream-task-subscription*.rkt tests/upstream-resource-loss.rkt tests/upstream-task-loss.rkt tests/scenario-subscriptions.rkt
    raco make "$@" examples/greeter.rkt
    raco test "$@"

9.2 uses PLTCOMPILEDROOTS=$PWD/.cache/ci/compiled-9.2-effect. 9.3 uses
.cache/racket-9.3/bin on PATH and
MCP_RACKET_USER_HOME=$PWD/.cache/ci/package-home-9.3-current.
sh scripts/check-interop.sh passed 14 official Go probes.
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl passed.
Installed verification unsets PLTCOLLECTS, uses the 9.3 home as PLTUSERHOME,
runs raco setup --no-docs --check-pkg-deps --pkgs racket-mcp, then tests
subscription-client-validation, stdio-cancellation and subscription from the
source distribution: 73 checks passed. python3 scripts/package.py builds the
source ZIP; two builds were byte-compared. Logs have trailing whitespace removed.

GitHub run 34255401805 at 4bea66e is terminal startup_failure with zero jobs and
no check-run diagnostics. Its cause remains unestablished. Native macOS/Windows,
full independent conformance, the complete reconnect/failure matrix and the
full SDK release remain unverified; no full-suite claim is made here.
