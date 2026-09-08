# Composed interface manifests

The initial mounted-fragment regression failed three cases: the manifest was
empty, its tool-to-resource reference was absent, and generated documentation
omitted the mounted tool. Provider and application bodies throw if instantiated,
independently checking the inspection boundary.

Interface bindings now carry private compiler identity through renamed exports.
Static composition reads generated independent manifest submodules, rebases
resource identities and handles literal view transformations. Computed and
conditional mounts remain explicit unknowns. View policy descriptions survive
composition; docs, diagrams and diffs distinguish unknown surfaces.

## Final evidence

- Final focused compilation and 359 checks passed on Linux Racket 9.2 and 9.3.
- Final installed package dependency checks and the same 359 cases passed on 9.3.
- The broad 9.3 run passed compilation, 6,065 native checks, 1,301 core schema
  cases, 86 optional regex cases and Scribble.
- All 14 official Go interoperability probes passed.

The broad and Go runs preceded three final test-only additions and the final
computed-policy summary correction. Individual policy descriptions were unknown
already; the last patch propagates that information to dynamic-metadata. It does
not change runtime dispatch or view transformations. The final focused runs
include all 17 authored composition cases. full-runtime-source-sha256.json
records the broad run's Racket sources; final-policy-flag.patch is the subsequent
implementation difference. Earlier 355-check and 16-case logs are retained as
intermediate evidence. Trailing whitespace was trimmed from setup logs.

The focused runs compile all public modules and run manifest-composition, core,
domain, declaration-manifest, reference-manifest, manifest-reference-bindings,
manifest-external-identities, manifest-provider-phases, manifest-diagram,
manifest-docs, manifest-diff, manifest-capability-parity, phase-exports,
module-imports, extension-phase-matrix, view-scopes, view-adapters and view-effects.
Use scripts/racket-env.sh with version-specific Racket and package homes; 9.2
uses an isolated PLTCOMPILEDROOTS. Installed checks omit PLTCOLLECTS and run the
files under .cache/distribution/racket-mcp/tests.

```sh
raco make mcp/*.rkt tests/manifest-composition.rkt
raco test tests/manifest-composition.rkt
sh scripts/check.sh
sh scripts/check-interop.sh
raco setup --check-pkg-deps --pkgs racket-mcp
python3 scripts/package.py
```

Native macOS/Windows verification and the complete SDK release gates remain open.

Consecutive source ZIP builds after the final ledger update produced identical
SHA-256 hashes; cmp passed. SHA256SUMS records the final distribution digest.
