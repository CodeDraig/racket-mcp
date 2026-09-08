# Final source distribution verification

Two clean builds by scripts/package.py are byte-identical and pass ZIP integrity
checks. The 1,849-file archive includes mcp/build.rkt and REMAINING.md and excludes
compiled files, caches, node_modules, git data and test-artifacts.

SHA-256: 7c0e1840b66e297823cd5cdfa4c8fbe5e2f76da407be9d1b18138b15790cee2f
Size: 4526232 bytes.
SDK source: 5731907dfc4833fc0e235e0bcd50fa12bd30df27.

compare-archives.py records the exact procedure; reproducibility.json and
archive-build.log retain its result. The local deliverable is
.cache/distribution/racket-mcp-0.1.zip. Package dependency checks and final installed
checks are in ../declared-build-20260908/installed-corrected-9.2.log and
installed-corrected-9.3.log. The earlier installed logs in this directory predate
the declared identity integration and are preserved as historical evidence.
