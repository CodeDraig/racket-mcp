# Full source verification after subscription validation

Source commit: 6184c15d2d403179e197a1f6c23d998035db9525.
Linux x86_64, Racket 9.3. The process exited 0 after approximately 14 minutes.

Command from the repository root:

    env PATH="$PWD/.cache/racket-9.3/bin:$PATH" MCP_RACKET_USER_HOME="$PWD/.cache/ci/package-home-9.3-current" sh scripts/check.sh

The command verified pinned elicitation/Tasks schema extraction, compiled the
public modules, examples, tests and dev fixtures, and passed 6,193 native tests,
1,301 pinned core JSON Schema cases, 86 optional regex cases and the Scribble
manual build. No core/regex cases failed or were unsupported. The duplicate raco
registration warning reflects the source and locally installed package entries.

SDK and test source remained unchanged throughout this run. Separate direct-entry
experiments used temporary files, Racket 9.2 and its isolated compiled root;
their evidence is in ../default-launch-capture-probe-20260908. Only evidence and
ledger documentation were written while the full suite ran. Log trailing
whitespace was removed before hashing. The final source ZIP was rebuilt twice
and byte-compared after the ledger update; its hash is recorded separately.

This is Linux 9.3 verification, not native macOS/Windows or full independent MCP
conformance. Default executable sealing and the other recorded release gates
remain open. Installed and Go checks for these runtime changes are recorded in
../subscription-closure-20260908.
