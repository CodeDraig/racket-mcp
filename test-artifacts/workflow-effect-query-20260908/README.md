# Workflow effect binding query gap, 2026-09-08

A workflow extension queries `writer` in the effect binding space after a
`perform` using that adapter. The query currently fails during expansion. The
initial source and diagnostic are retained; the diagnostic names the cache
probe path from the actual run. This is not a runtime adapter lookup failure.

The compiler collects effect identities after workflow extensions have expanded,
then emits `workflow-effects`. The public extension API therefore still needs
an explicit binding model for queries during stage expansion. This probe does
not establish forward-reference or branch-scope semantics and no correction is
included with the workflow match patch.

`host-probe.rkt` compiles successfully with the same query in an ordinary handler
expression macro. The observed gap is therefore specific to workflow-stage
extension expansion before the emitted effect environment exists. This compile
probe does not invoke an adapter or count as runtime verification.


The implementation now supplies a per-stage lexical effect context and emits
matching handler scopes. `perform` introduces its adapter in its input expression
and subsequent stages of its sequence. Branch/block-local adapters do not escape;
inherited adapters survive joins. Generated adapter references have a separate
checked scope. Adapter identifiers retain private macro scopes. Same-spelled
workflow values and effects are both visible by placing the generated effect
scope inside the value scope; ordinary host let bindings retain Racket shadowing.

The new test checks workflow-stage and ordinary expression queries together,
including renamed imports, private adapters, branches, match, let, suspension,
retries, effect counts and shifted phases. The 9.3 focused selection passed 96
checks and the final scope test passed 11. All 14 Go probes passed. An isolated
9.2 compilation cache passed 40 focused checks. A source-only combined run failed
two older dynamic-require assertions. Committed c05b670 reproduces both errors
when workflow-extension-bindings runs before domain-bindings in a source-only
`raco test --direct` process; domain-bindings alone passes. This is a pre-existing
source-only test-order issue, not established as a regression from this patch. Installed dependency setup and 40 installed checks passed. The separate language
probe passed four checks, including manifest access without parent instantiation.
Full 9.3 validation passed 5,789 native checks, 1,301 core schema cases,
86 optional regex cases and Scribble. Full 9.2 validation is running in a separate
source copy whose 608 source inputs match the worktree (source-inputs-9.2.json).
Saved logs have trailing whitespace trimmed.

Unsuccessful logs include a generated adapter reference missing its former
hoisted scope, a shifted-phase fixture import collision, an incorrect assertion
about fresh scopes on already-bound host identifiers, the reproduced value/effect
scope collision, and a fixture that assumed an unprefixed input identifier.
