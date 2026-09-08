# Separate collection extension acceptance, 2026-09-07

`examples/collections.rkt` imports the separate public `collection` extension and
uses it twice. A new official Go client probe checks the generated tool names,
resource-template identities, percent-encoded reads, independent search data and
completion targets. Expected values are authored independently of compiler output.

The native regression checks renamed extension imports, colliding host helper
names, exactly one entries evaluation per invocation, and search/read/completion
after a view applies namespaces and a URI mapping. Eight new checks passed on
Linux Racket 9.2 and 9.3; the 9.3 extension selection passed 38 checks in total.

`sh scripts/check-interop.sh` passed all 14 probes on Racket 9.3. Scribble and
`python3 scripts/package.py` passed. Installed CLI validation is recorded in
`installed.log`. The installed check initially failed because the CLI resolved relative imports
against its working directory. A three-case regression reproduced that defect;
the command now sets the source load directory and counts source lines before
expansion. The final CLI/extension selection passed 55 checks, and the same
installed command passed after rebuilding the package. The protocol/runtime
engine is unchanged; a new full native/schema run was not performed. The three
CLI regressions also passed source-only on Racket 9.2. The previous
full baseline remains 5,109 native checks and 1,301 core schema cases.

A separate failing compiler probe is retained as `workflow-binding-probe.rkt`
and its log. A workflow extension calling `require-mcp-binding` on an argument
cannot recognize that argument as a workflow value during stage expansion.
This is an open compiler/API defect, not a failure of the collection probe.
The source was run from `.cache/tmp`; it is retained here for reproduction and
is not included in the passing test selection. Full domain extension semantics
and the other release gates remain open.
