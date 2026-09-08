# Completion identities

The baseline generated valid resource and prompt completions with the same
display name and argument. Both the direct and mounted manifests failed diffing
with duplicate declaration identities. Runtime completions have separate target
identities, so display-name indexing lost information from a valid interface.

Resource completions now carry lexical references, including defining provider,
binding name and local target where resolved. Existing mount prefixing, provider
rebasing and resource resolution carry those references through transformed
interfaces. Diff identities use the resolved published resource URI/template or
prompt name together with target kind and argument. Unresolved legacy targets
are explicit review items, including unmatched counterparts they could retain.

Eight authored cases cover same-named resources and prompts, transformed URI/name
dispatch, duplicate resolved targets under aliases, legacy unresolved metadata,
renamed imported bindings, and expansion rejection of an excluded target. The
initial focused completion and resource-diff run passed 51 checks on Linux 9.3.
A runtime probe then exposed that a local completion targeting a transformed
mounted resource was rejected as absent. Resource completions now resolve by
declaration identity at construction, reject ambiguous or absent matches, and
detect duplicate argument routes after resolution. Static composition checks
duplicates again after resolving imported targets. Tests exercise ordinary data
construction and actual imported-target dispatch.

Before the runtime correction, the full Linux 9.3 run passed 6,099 native tests,
1,301 core schema cases, 86 regex cases and the manual build. Both versions and
the installed package passed 231 focused tests, and all 14 Go probes passed.
The runtime change was developed in an isolated checkout while the full suite
kept its original source tree. It passed 53 checks on Linux 9.2 and 9.3 there.
The final combined source passed 442 focused checks on Linux Racket 9.2 and 9.3
and in the installed 9.3 package. Installed setup passed dependency checking.
The installed run executes each of the 23 named files separately; its individual
passing counts sum to 442. A fresh full suite was started on the final combined
source passed 6,101 native tests, 1,301 core schema cases, 86 regex cases and the
manual build. This remains separate from the earlier 6,099-test observation.

A subsequent raw-descriptor probe reproduced another parity gap: make-runtime
discarded normalized completion targets after validating a raw interface, so
dispatch to the remapped URI failed with Unknown completion target. A correction
was developed in /tmp/racket-mcp-completion-runtime (runtime.rkt and the additional
assertions in manifest-completion-identities.rkt). It retains the
normalized interface only when completion targets changed, preserving identity
for already-normalized descriptors. The isolated correction passed 101 grouped
checks plus the standalone probe on 9.3, and 102 together on 9.2. It was copied
into the main checkout only after the full suite finished. Final focused results
are recorded separately; the 6,101-test result precedes this final correction.
The final source passed 442 checks on each Linux version and from the installed
9.3 package (23 separately executed files), dependency setup, all 14 Go probes,
and the manual build. Files prefixed raw-final contain these final observations.
The distribution was built twice and byte-compared; distribution-SHA256SUMS
records the ZIP digest. Artifact logs are excluded from that distribution.

Commands use scripts/racket-env.sh, version-specific package homes and an
isolated PLTCOMPILEDROOTS for 9.2. Dynamic manifest fixtures are explicitly made.
Installed tests use the copied source package with PLTCOLLECTS unset.

```sh
raco make mcp/*.rkt tests/*.rkt
raco test tests/manifest-completion-identities.rkt tests/manifest-composition.rkt tests/composed-reference-checks.rkt tests/manifest-diff.rkt tests/manifest-resource-identities.rkt
sh scripts/check.sh
sh scripts/check-interop.sh
raco setup --check-pkg-deps --pkgs racket-mcp
python3 scripts/package.py
```

This is evidence for completion identities, not closure of the full compiler,
conformance or native macOS/Windows release gates.
