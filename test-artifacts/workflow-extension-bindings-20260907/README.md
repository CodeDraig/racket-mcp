# Workflow extension binding queries, 2026-09-07

The previous collection acceptance work retained a failing workflow query in
`../collection-extension-20260907/workflow-binding-probe.rkt`. A stage extension
could not recognize a workflow argument through the public binding API.

Stage expansion now receives the compiler's already parsed lexical value context
for the extent of that expansion. Scope-aware comparison normalizes the current
macro introduction and use-site scopes, preserving other scopes. No name-based
or global registration table is introduced. Pending values take precedence over
same-named outer declaration metadata.

The initial context implementation still failed because the calling compiler and
nested transformer see different current introduction scopes. The scope trace
is retained. After correcting that boundary, the original probe exposed a second
failure: locally generated output binders retained use-site scopes and could not
be referenced by later stages. Binding positions now remove those use-site
scopes; expressions and private introduced scopes retain their hygiene.

The separate `checkpoint-copy` extension uses only the public API and emits core
checkpoint syntax. Tests cover arguments, preceding checkpoints, nested/renamed
extensions, lexical blocks, branches, future/out-of-scope values, fresh scopes,
actual host shadowing, an outer schema shadowed by an argument, shifted phases,
grouped inputs and effect results. Retrying the completed input/effect workflow
returns its recorded result without repeating the effect.

The focused Racket 9.3 selection passed 62 checks, including phase probes 0-2.
The new regression passed nine source-only checks on Racket 9.2. Two preliminary
fixture errors are retained separately: a misplaced syntax-parser directive and
reversed input/key parameters in the test adapter.

All 14 Go probes, package dependency setup and installed CLI validation passed.
An initial installed command pointed at retained test artifacts, which are
intentionally excluded from the distribution; the corrected command checks the
packaged regression module. The full suite passed 5,129 native checks, all 1,301 pinned core schema cases,
and the Scribble build. Saved logs have trailing whitespace trimmed. The overall SDK release remains unfinished.


Commands used the project-local Racket 9.3 installation and package home:
`sh scripts/check.sh`, `sh scripts/check-interop.sh`, `python3 scripts/package.py`,
installed `raco setup --check-pkg-deps --pkgs racket-mcp`, and installed
`raco mcp check .cache/distribution/racket-mcp/tests/workflow-extension-bindings.rkt`.
The Racket 9.2 run used source-only `raco test --direct` for the new regression;
it is not a new full 9.2 run. macOS and Windows remain unverified.
