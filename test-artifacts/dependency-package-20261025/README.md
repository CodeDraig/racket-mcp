# Installable patched dependency — 2026-10-25

Packaging work based on `e116d0555fd76cee95940f7e07d67c944e0fb31e`.
The package is `mcp-syntax-spec-v3`, version `0.1.0.2`, under
`packages/mcp-syntax-spec-v3`. Its collection has the same name, allowing it to
coexist with upstream `syntax-spec-v3`. The SDK now imports that collection and
its dependency source is:

```
https://github.com/CodeDraig/racket-mcp.git?path=packages/mcp-syntax-spec-v3#main
```

This source path becomes available after the changes are pushed. No catalog
listing, commit, push, or repository-visibility change was performed in this task.
The automatic-install probe substituted a loopback HTTP ZIP URL for that one
metadata value; it does not establish successful installation from GitHub.

## Completed checks

Linux x86_64, Racket CS:

| Check | Result |
| --- | --- |
| SDK native tests, Racket 9.3 | 6,852 passed |
| SDK native tests, Racket 9.2 | 6,852 passed |
| Pinned schema suite, each Racket version | 1,301 passed |
| Optional regex suite, each Racket version | 86 passed |
| SDK compilation and Scribble manual, each version | Passed |
| Patched dependency upstream tests, Racket 9.3 | 462 passed |
| Package reproduction/integrity regressions | 4 passed |
| Upstream and patched collections installed and imported together | Passed |
| Final standalone ZIP install, phase 0/1/2 imports, manual and dependency check | Passed |
| Automatic dependency download with local HTTP source substitution | Passed; patched package marked auto-installed |
| Installed SDK CLI and greeter | Passed; Ada and Grace responses, clean EOF exit 0 |
| Fresh repository-root setup and dependency checks after archive exclusion fix | Passed; zero compiled archived probes |

The complete 9.2 CI report and individual 9.3 step results are saved below.
The initial 9.3 CI process returned failure at its package check; the corrected
fresh repository-root check supplies the acceptance for that step. It was not
reported as an uninterrupted passing CI run. No runtime source changed for that
packaging correction, so the successful native suites were not repeated.

## Preserved failures and corrections

- The first two-archive install command used `racket-mcp-0.1.zip` without an
  explicit package name. Racket rejected the inferred name. The same bytes under
  `racket-mcp.zip` installed successfully alongside the dependency archive.
- An initial 9.2 full-suite attempt ran unpacked source tests against a separately
  installed SDK without the normal CI source-root environment and compilation.
  It produced command-observation failures and a domain-binding expansion error.
  Adding `PLTCOLLECTS` alone still left three command-observation failures. A fresh
  source tree run through `scripts/ci.py` supplied the normal compilation and
  consistent module identity; all 6,852 native tests then passed. No test assertions
  or runtime implementation were changed to accommodate this harness mistake.
- The initial 9.3 repository-root package check compiled historical probe sources
  in `test-artifacts/`, producing a missing-helper error and undeclared-dependency
  reports. Package-root omission metadata did not exclude that collection from
  `raco setup --pkgs`. Added `test-artifacts/info.rkt` with compilation and testing
  omitted, following the existing per-collection policy. A fresh full-root
  installation and dependency check passed without compiling archived probes.

## Provenance and artifacts

All 224 vendored upstream files still match `vendor/LOCK.json`. The standalone
package contains 227 files, including its licenses, a package-specific guide,
and `MCP-PATCH.json`. The four compiler-patch hashes match the already prepared
patches; collection names and import references changed for coexistence.

The final dependency archive is reproducible with:

```sh
python3 scripts/prepare-syntax-spec.py --check \
  --archive .cache/patched-package-20261025/mcp-syntax-spec-v3.zip
```

SHA-256:

```
e72cfaa1f6bddf3f58f5cfe7a3aad1894f23d26170781fd7275acbc21bd92374
```

The final dependency differs from the runtime-tested snapshot only in its README
notice and the corresponding manifest entry. A separate fresh installation and
dependency/manual check tested that final ZIP. All 706 Racket and manual sources
compared between the final checkout and both SDK test snapshots are identical.

`checks/` retains the actual runner scripts, commands, exit statuses, failed
attempts, HTTP requests, smoke responses, and source-equality checks.
`racket-9.2/` and `racket-9.3/` retain CI logs and reports. `inputs.json` records
source hashes; `SHA256SUMS` covers the evidence files.

The SDK packager now emits a standalone dependency ZIP alongside its existing
SDK ZIP and records both hashes. Its ZIP inspection found the dependency and
license files, with no compiled or Python cache entries. Later documentation
updates do not imply a rebuilt SDK archive.

Go interoperability and MCP/OAuth conformance were not rerun for this packaging
change. Existing qualified results and accepted limitations remain applicable;
this receipt is not an unqualified protocol-conformance claim. macOS and Windows
were not tested. The repository remains public; the changes in this receipt are
local pending commit and push, followed by the actual GitHub installation check.
