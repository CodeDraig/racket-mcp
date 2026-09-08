# Language acceptance audit, 2026-09-08

The approved language invariants map to these concrete checks. This closes the
specified acceptance surface, not every possible combination of Racket programs.
Default automatic build capture is tracked separately under BUILD.

| Invariant | Evidence |
|---|---|
| Ordinary module definitions/imports/exports/macros/submodules; fragment and generated entry point | compiler.rkt, core.rkt, direct-entry.rkt, extensions.rkt, phase-exports.rkt, manifest-provider-phases.rkt. Generated serving name is hygienic; parent instantiates once per direct invocation; fragments provide manifests without starting a server. |
| Required/optional/default arguments; declaration and default evaluation order/count; missing/null/false | core.rkt, declaration-schemas.rkt, prompt-codecs.rkt, declaration-contracts.rkt. Earlier arguments are available to later defaults; present arguments skip default evaluation. |
| Duplicate binders and wire names; conflicting clauses; source-attached failures | declaration-wire-bindings.rkt checks the repeated binder at its exact source line even under distinct lexical scopes. New mcp-grammar-contracts.rkt supplies nine malformed public examples with source-attached expansion failures. |
| Literal schemas checked at expansion; computed expressions deferred | declaration-schemas.rkt, declaration-reader-literals.rkt, schema-construction.rkt, tool-schema-objects.rkt. Lexical quote shadowing and reader values are tested; arbitrary expressions are not evaluated to infer schemas. |
| Binding classes, imports, aliases, phases and host shadowing | domain-bindings.rkt, phase-exports.rkt, phases.rkt, extension-phase-matrix.rkt, workflow-extension-bindings.rkt, workflow-effect-bindings.rkt. Phase 0/1/2 queries, re-exports, wrong-kind source errors, lexical value/effect distinction and sibling/future-scope exclusion are exercised. |
| Workflow grammar, persistent codecs and suspension boundaries | branches.rkt, workflow-match.rkt, workflow-match-restart.rkt, extensions.rkt, task-boundary-language.rkt, workflow-construction.rkt. Generated invalid stages and suspension hidden in host expressions are rejected; non-data values cannot cross a codec boundary. |
| Public extension API, private IR boundary and separate collection example | mcp/extension plus the documented expansion-time binding query API; extensions.rkt, extension-bindings.rkt, extension-phase-matrix.rkt, collection-extension.rkt and the official Go collection probe. Collection entries evaluate once, helpers remain hygienic, and mapped completion works. |
| Equivalent ordinary descriptor construction and dispatch contracts | declaration-contracts.rkt compares macro/data discovery, schema and call outcomes; declaration-schemas.rkt and workflow-construction.rkt validate ordinary factories and raw descriptors before execution. Shapes/codecs/resources/prompts are exercised by domain.rkt, prompt-codecs.rkt, domain-workflows.rkt and the same runtime validation path. |
| Static manifests, dynamic unknowns and non-instantiating tools | declaration-manifest.rkt, manifest-side-effect.rkt, manifest-examples.rkt and cli-artifacts.rkt; unknown metadata stays marked, examples stay syntax data, and throwing application initialization is not run by artifact inspection. |
| Reference arity, composition/removal/renaming | Already closed in test-artifacts/reference-acceptance-20260908. This audit does not reopen it or promise arbitrary host-program reference inference. |

The nine new negative grammar probes pass on Linux Racket 9.2 and 9.3 after
repository integration. The combined 20-case logs (including eleven durability
cases) are in ../durability-boundaries-20260908/integrated-9.2.log and
integrated-9.3.log. Both exited zero; the latter also builds the manual after
correcting stale reference-analysis status prose. LANGUAGE is removed.
