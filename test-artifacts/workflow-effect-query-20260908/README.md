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
