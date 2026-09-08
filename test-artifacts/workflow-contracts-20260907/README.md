# Workflow and codec construction contracts, 2026-09-07

The initial runtime regression accepted 15 invalid values among 16 checks.
`reproduced.log` retains those failures. Two earlier test-file parenthesis errors
are retained separately as fixture failures; they do not establish runtime
behavior.

Workflow factories, descriptor installation and direct execution now share
validation of identities, callback arities, stage kinds and fields, schemas,
codecs, input identities and control-flow destinations. Reachable fallthrough
and programs without reachable completion fail before creating an instance.
This is structural validation, not a proof that arbitrary host code terminates.

Raw value/string codecs receive the same field checks as their factories before
registration or encoding/decoding. Tests verify that invalid values do not invoke
callbacks or create stored instances, and that valid raw workflows and codecs
still execute and round-trip successfully.

The focused Racket 9.3 selection passed 119 checks. The new regression passed 43
source-only checks on Racket 9.2. Distribution construction, installed package
dependency setup and installed `raco mcp check` passed on Racket 9.3. Saved logs
have trailing whitespace trimmed.

The final Racket 9.3 full run passed 5,109 native checks, all 1,301 pinned core
schema cases, and the Scribble build. All 13 official Go probes passed.

Commands: `sh scripts/check.sh`, `sh scripts/check-interop.sh`,
`python3 scripts/package.py`, installed `raco setup --check-pkg-deps --pkgs
racket-mcp`, and installed `raco mcp check examples/approval.rkt`, with the
project-local Racket 9.3 installation and package home. The 9.2 focused run used
`raco test --direct` with `use-compiled-file-paths` set to `null`.

This patch does not complete the SDK release gates or establish a new full
Racket 9.2 or macOS/Windows result.
