# Ordinary workflow construction parity

The baseline reproduced an ordinary make-workflow call inside the module context
that did not retain its build. Initialization expressions now run under that
build after its acquisition, including host calls and lifted expressions.
Transformer phases and submodules retain their own lifetimes. Missing acquisition
bindings fail expansion. The boundary's completion expression stays outside the
initialization parameterization.

Three authored cases cover direct/indirect/lifted constructors, multiple values,
evaluation order and count, unsealed rejection, explicit sealing and successful
workflow execution, parameter restoration on failure, and an invalid acquisition.
Both Linux Racket versions passed the 33-check group with existing context/restart
cases, then all three final file cases after adding the acquisition diagnostic.

Commands use version-specific package homes, an isolated compiled root on 9.2,
and explicit compilation of the dynamic restart worker. The five test files are
module-context-data-api, initialized-module-context, module-finalization,
module-build-context and module-build-context-restart. Installed checks unset
PLTCOLLECTS and run raco setup --no-docs --check-pkg-deps --pkgs racket-mcp.
The distribution is built using python3 scripts/package.py and compared twice.
Log trailing whitespace is removed only. The broad protocol suite and manual were
not repeated for this private compiler correction. Default integration and the
production runtime identity policy remain open; native macOS/Windows are unverified.

Installed 9.3 setup passed dependency checking and all 34 combined tests. The
source ZIP was built twice and byte-compared; distribution-SHA256SUMS records
the digest. All remaining release gates remain open.
