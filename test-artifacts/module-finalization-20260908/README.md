# Module initialization completion boundary

module-begin/finish fully expands the chosen module-begin, drains its lifted
forms, and appends a trusted completion expression. Seven cases verify ordering,
failures before completion, retries, recursive lifts, one expansion, hygiene,
submodule behavior, contracted exports, and the actual MCP compiler's independent
manifest and dispatched tool. The custom-language submodule fixture initially
expected no second callback even after explicitly loading that submodule; its
expectation was corrected to preserve normal module semantics.

This is a private compiler component. Default workflow construction and sealing
are unchanged. The successful-load boundary can now be integrated without
mistaking an earlier module-end capture for successful initialization.

Commands: version-scoped raco make tests/module-finalization.rkt;
raco test tests/module-finalization.rkt tests/module-build-context.rkt;
raco setup --no-docs --check-pkg-deps --pkgs racket-mcp;
python3 scripts/package.py (two builds followed by cmp).
9.2 uses an isolated compiled root; installed 9.3 checks unset PLTCOLLECTS.
Log trailing whitespace is removed. The broad suite and manual were not repeated
for this private additive component; native macOS/Windows remain unverified.

All 12 focused checks passed on Linux Racket 9.2, Linux Racket 9.3, and the
installed 9.3 distribution. Installed dependency checking passed. The source ZIP
was built twice and byte-compared; distribution-SHA256SUMS records its digest.
