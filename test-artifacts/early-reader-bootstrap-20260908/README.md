# Early reader bootstrap observation

The reader starts in #%kernel and installs kernel observation before loading the
ordinary observer and syntax/module-reader implementation. The installed kernel
hook transfers records and continues forwarding retained loader callbacks. The
existing scoped hook still closes after its extent. Installed seeds preserve
newer records and module-registry separation. Reader exports preserve arities.

The cold-source regression inspects the existing capture-baseline fixture's graph:
no ordinary dependency lacks code evidence; 22 predefined modules remain. This
is not automatic runtime identity or workflow sealing. A transient scoped-reader
prototype left ten ordinary gaps; those callbacks were retained beyond its scope.

The initial broader run found that stamping a kernel entry with an ordinary
metadata provider loads racket/base before observation starts. The startup
provider now uses only #%kernel. An intermediate static import of that provider
from the compiler helper still left the provider itself outside observation;
those two failures per version are retained in final-9.*.log. They are superseded
by verified-9.*.log, each containing 212 passing selected checks. The standalone
provider-correction.log contains 11 passing startup cases. The tests also query
the metadata-selected provider for language-information delegation.

Reproduction, from the repository root after sourcing scripts/racket-env.sh:

    set -- tests/reader-bootstrap.rkt tests/kernel-observation.rkt tests/observation-install.rkt tests/module-observation.rkt tests/core.rkt tests/compiler.rkt tests/loader*.rkt tests/bootstrap-sdk-restart.rkt tests/command-observation.rkt tests/compiled-identity.rkt tests/retained-capture.rkt tests/module-context-data-api.rkt tests/initialized-module-context.rkt tests/module-finalization.rkt tests/module-build-context*.rkt
    raco make mcp/*.rkt examples/*.rkt dev/*.rkt "$@"
    raco test "$@"

Linux Racket 9.2 uses PLTCOMPILEDROOTS=$PWD/.cache/ci/compiled-9.2-effect.
9.3 uses .cache/racket-9.3/bin on PATH and
MCP_RACKET_USER_HOME=$PWD/.cache/ci/package-home-9.3-current.
sh scripts/check-interop.sh passed all 14 Go probes. The manual built using
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl.

Installed checks unset PLTCOLLECTS, use the 9.3 home as PLTUSERHOME, run
raco setup --no-docs --check-pkg-deps --pkgs racket-mcp, then test reader-bootstrap,
kernel-observation, observation-install and compiled-identity from
.cache/distribution/racket-mcp/tests. python3 scripts/package.py builds the source
ZIP; two final builds are byte-compared. Logs have trailing whitespace removed.

The prior 6,193-test full result predates this change. Native macOS/Windows and
full release verification remain open. Complete runtime baseline identity and
default workflow capture/sealing integration are not implemented by this change.

Installed dependency setup and all 29 installed checks passed. The final ZIP was
rebuilt twice and byte-compared; distribution-SHA256SUMS records its digest.
