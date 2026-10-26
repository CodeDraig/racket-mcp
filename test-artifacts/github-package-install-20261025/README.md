# Public GitHub package installation — 2026-10-25

Verified packaging commit `917c1bfffbd81fbe0e72c6d9b769dd42352d66a6` after pushing
it to the public repository. Both installations used the actual GitHub source,
with no local source-URL substitution or preinstalled MCP packages.

## Results

Fresh isolated package homes on Linux x86_64, Racket CS 9.2 and 9.3:

- Requested only `racket-mcp`; Racket automatically installed `mcp-syntax-spec-v3`.
- Both installed package checksums matched the pushed commit above.
- `raco mcp --help` passed.
- `raco setup --check-pkg-deps --pkgs racket-mcp mcp-syntax-spec-v3` passed,
  including documentation generation.
- All 226 files listed in the dependency's provenance manifest matched their hashes.
- No archived probe sources under `test-artifacts/` were compiled.
- The installed greeter returned `Hello, Ada` and `Hello, Grace`, then exited 0
  on standard-input EOF, with empty stderr.
- All commands completed successfully; there were no failed attempts in this run.

The installation command was:

```sh
raco pkg install --auto --batch --no-docs --name racket-mcp   'https://github.com/CodeDraig/racket-mcp.git#main'
```

Each run selected the appropriate Racket executable through PATH, used a new
PLTUSERHOME, and removed PLTCOLLECTS. `verify.py` records the complete commands and
environment setup. Per-version logs and `results.json` retain exit statuses,
installed source URLs/checksums, timings, and greeter responses.

This is delivery verification, following the complete native/package validation
in [the packaging receipt](../dependency-package-20261025/README.md). The full
native, Go, and protocol-conformance suites were not repeated for this push.
The later commit recording this receipt changes documentation and evidence only;
it does not change the package implementation verified here.

The repository remains public. The Racket catalog form has not been submitted.
