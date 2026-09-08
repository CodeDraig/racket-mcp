# Declaration construction and wire bindings, 2026-09-07

Initial regression: 28 malformed dynamic declarations/interfaces were accepted.
The retained `contracts-initial.log` records 28 failures among 29 checks. Shared
factory/interface contracts now reject those values without invoking handlers.
The expanded tests also compare DSL/data dispatch and validate published Tool,
Resource and Prompt definitions against the pinned core wire schema.

A separate expansion probe used argument identifiers with distinct lexical
scopes but the same JSON spelling. Tool, resource, prompt and workflow expansion
accepted them; a shape failed at a generated accessor without the repeated
binder's source. `scoped-binders-initial.log` retains those results. The new
wire-name check identifies the repeated source binder for all five forms.

Focused language/domain/workflow/phase testing passed 278 checks before adding
three raw-interface runtime-installation cases. The full run includes those
additional cases. The workflow structs moved to a private shared module solely
to permit descriptor type checks without importing the execution engine; public
workflow exports remain available.

Two preliminary fixture errors were corrected: the expanded contract test needed
`mcp/completion`, and the expansion fixture needed `mcp/lang` as its module
language. An initial command continued after the import compilation failure and
also hit stale workflow bytecode; the corrected command stopped on compilation
failure and rebuilt dependent tests. Those failures are not runtime regressions.

Reproduction uses the project-local Racket 9.3 installation:

```sh
env PATH="$PWD/.cache/racket-9.3/bin:$PATH" \
  MCP_RACKET_USER_HOME="$PWD/.cache/ci/package-home-9.3-current" \
  sh scripts/check.sh
```

Final Linux/Racket 9.3 verification passed 5,066 native checks, all 1,301 core
schema cases, Scribble, package dependency checks and installed `raco mcp check`.
All 13 Go probes passed. The final source-only Racket 9.2 run passed 103 checks.
Trailing whitespace was trimmed from the saved package setup log.
Full descriptor/codec/workflow constructor parity and the other SDK release
gates are not claimed complete by these checks.

The first full run ended with 8 failures among 4,905 recorded checks; aborted
modules prevented the normal total. Three assertions expected the existing
non-symbol argument diagnostic, which is now preserved separately from the new
uninterned-symbol error. Existing data callers passed `#f` for absent server
instructions; the constructor now normalizes this to the existing empty-string
default, and wire/discovery plus static-manifest parity tests cover it. One
subscription fixture had a one-argument handler for a resource with no arguments;
it now has the correct arity and an actual resource-read assertion. The affected
selection passed 308 checks, followed by 143 manifest/contract checks.

An initial two-file Racket 9.2 source-only run spawned child processes, which did
not inherit the source-only parameter and tried to load 9.3 bytecode. The corrected
command uses `raco test --direct` under `use-compiled-file-paths` set to `null`.
The final source-only run includes the normalization and manifest checks.
