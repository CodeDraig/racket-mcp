# Composed reference checks and resource identities

The initial probes reproduced two defects: a local handler could reference a
resource explicitly removed by its mount without an expansion error, and two
hygienic resource declarations sharing a public name and source location could
not be resolved to their separate mounted targets.

References now match the provider and actual module-binding name. Diagnostic
locations do not participate in matching. Static view exclusions survive
fragment re-exports; absent and ambiguous references receive source-attached
errors. Another mount can supply an excluded resource, while computed mounts
defer absence checks to runtime. Valid cases are instantiated and checked using
their namespace's accessors, returning ordinary public URI/name summaries.

Binding names are encoded as strings. Initial focused 9.2 and full 9.3 runs
exposed uninterned-symbol write/read failures. The isolated correction passed
65 checks on 9.2. A later main 9.3 focused run read an old compiled dynamic
fixture; explicitly compiling manifest-rich.rkt refreshed it and all 35
declaration-manifest checks passed. Those failed observations are retained.

Known resources are compared by URI/template, allowing shared display names.
Unique unmatched names retain a URI-replacement report only with resolved
resource surfaces and no dynamic mounts; unknown addresses are review-required.
Additional probes reproduced false URI replacement and removal claims when
unknown URIs or dynamic mounts could retain the old identity. The final finite
oracle independently enumerates concrete completions of partial URI snapshots
and checks every definite URI-loss report against each possible world.
The resource-diff baseline includes one initially invalid
duplicate-URI fixture that first collided on a local ID; the final fixture uses
distinct local IDs. An existing reference-retargeting fixture now gives its
second resource a distinct URI, representing a valid published interface.

Before the final diff uncertainty correction, 380 focused checks passed on Linux
Racket 9.2, 9.3 and from the installed 9.3 package. The full 9.3 log reports 6,090
native checks, 1,301 core schema cases, 86 optional regex cases and the manual
build. All 14 official Go probes passed on that source. These observations do
not cover the final diff correction and three added cases.

Final focused checks: 383 passed on Linux Racket 9.2, 9.3 and from the installed
9.3 package. Installed dependency setup passed. The final source contains 13
composed-reference cases and eleven URI-diff cases. The first final manual
invocation omitted +m and emitted cross-reference warnings; rerunning the project
command with +m completed without those warnings. Both logs are retained.
The source ZIP was generated twice and byte-compared; its hash is recorded in
distribution-SHA256SUMS. Artifact logs are excluded from the distribution.

Reproduction uses scripts/racket-env.sh with version-specific Racket and package
homes. 9.2 uses an isolated PLTCOMPILEDROOTS. The dynamic manifest fixtures must
be explicitly compiled after compiler changes. Installed tests run with
PLTCOLLECTS unset against .cache/distribution/racket-mcp.

```sh
raco make mcp/*.rkt tests/*.rkt
raco test tests/composed-reference-checks.rkt tests/manifest-resource-identities.rkt tests/manifest-composition.rkt tests/declaration-manifest.rkt tests/manifest-reference-bindings.rkt tests/manifest-diff.rkt
sh scripts/check.sh
sh scripts/check-interop.sh
raco setup --check-pkg-deps --pkgs racket-mcp
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl
python3 scripts/package.py
```

The focused logs name the complete 20-file set. Trailing whitespace was trimmed
from retained failure/setup logs for Git checks. The original SDK release scope
is unchanged; remaining release and native macOS/Windows gates stay open.
