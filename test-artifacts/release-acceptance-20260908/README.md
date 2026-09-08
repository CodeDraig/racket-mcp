# Original-plan acceptance map

This maps the approved plan to implementation and behavioral evidence. It does
not resurrect completed historical checklists. The user-selected declared-build contract is implemented; final Linux release
checks pass and macOS/Windows remain externally unverified.

| Original acceptance requirement | Implementation / evidence |
|---|---|
| Valid/invalid syntax, hygiene, evaluation order, imports, renaming, phases and source locations | language-acceptance-20260908 audit; native core, declaration-schemas, declaration-wire-bindings, phase-exports, extension-phase-matrix, workflow-effect-bindings and mcp-grammar-contracts tests. |
| Macro and ordinary descriptor API equivalence | declaration-contracts, declaration-schemas, workflow-construction and module-context-data-api tests; ordinary SDK constructor/reference manual. Declared ordinary loading is covered by declared-build and declared-build-cli tests. |
| Resource references through composition, renaming and removal | reference-acceptance-20260908; interface-references, composed-reference-checks, manifest-composition and completion-reference suites. |
| Schema composition/dynamic refs/exact numbers/missing-null-false/malformed schemas/limits | Pinned schema suite: 1,301 cases; 86 regex compatibility cases; native core, schema-construction, schema-limits, schema-unicode-ranges, declaration-reader-literals and JSON decoding tests. Optional format assertions remain outside annotation-default scope. |
| Protocol versions/capabilities/envelopes/concurrent IDs/framing/headers/Unicode/interrupted streams | wire-acceptance-20260908 audit and conformance-closure-20260908; independent core/client checks and native transport suites. |
| Subscription acknowledgement/filtering/multiple listeners/overflow/closure/reconnection | wire and subscription closure audits; native subscription policy/client validation/HTTP scopes/loss tests; both-direction official Go resource feed probes. |
| Prompt/resource input, nested rendering, partial responses, decline/cancel, out-of-band completion | domain-workflows, embedded-workflows, input-groups, scenario-conflicting-inputs, task-notifications and render provenance tests. New mcp-render-boundaries process kills close parent/child commit gaps. |
| Checkpoint/effect restarts, duplicate/concurrent retries, expiry, ownership, arguments and code compatibility | durability-boundaries-20260908 transition map and 11 new process-kill cases; existing 18 effect crash combinations and task/recovery/clock tests. Captured-loader compatibility and user-declared ordinary build identities are tested; the latter puts update responsibility on the application. |
| Transactional/idempotent/manual recovery semantics | scenario-effect-crashes, restart, recovery-races, recovery-codec-lock and task-recovery-process tests. Recorded keys do not imply exactly-once behavior. |
| Tasks durability/input/ownership/cancellation races/terminal immutability | tasks, task-keys, task-restart, task-boundary-restart, checkpoint-lock and task-recovery-process tests; dedicated independent Tasks 43-success run (refreshed after the task guard correction) with explicit header disagreement and notification-harness gap. |
| Commit-driven freshness without authorization leakage | shared-resource-policy-20260908, workflow-freshness, task-freshness, external-change-restart and shared-resource-freshness. Explicit per-owner fanout and authorization-aware delivery are documented. |
| Manifest inspection avoids application instantiation; transformer trust boundary retained | manifest-side-effect, manifest-examples, cli-artifacts, declaration-manifest and extension tests. Docs exports source examples separately and never presents assertions as run results. |

| Planned deliverable | Location / release status |
|---|---|
| Native client/server SDK, stdio and Streamable HTTP | mcp/stdio.rkt, mcp/http.rkt, mcp/runtime.rkt; runtime remains native Racket. Final conformance is qualified explicitly, not advertised as universal agreement. |
| Native JSON Schema 2020-12 validator and bounded JSON | mcp/schema.rkt, mcp/json.rkt and private validator modules; pinned official suites and local reference registry. No compile-time network fetching. |
| #lang mcp, equivalent library forms, schemas/shapes/domain references | mcp/lang/reader.rkt, mcp/lang.rkt, mcp/forms.rkt, mcp/descriptor.rkt, mcp/codec.rkt. Language and ordinary API reference built with Scribble. |
| Durable workflows, SQLite, effects and Tasks | mcp/workflow.rkt, mcp/storage.rkt, mcp/tasks.rkt; explicit state paths, random owner-bound handles, journals and recoverable uncertainty. |
| Composition, upstream adapters and freshness | mcp/composition.rkt, mcp/upstream.rkt, mcp/upstream-subscription.rkt, mcp/freshness.rkt; upstream-process-loss-20260908 closes real HTTP update/cancel uncertainty after bridge process death. |
| Authorization adapters and client flow | mcp/authorization.rkt, mcp/oauth.rkt and mcp/oauth-http-client.rkt; conformance closure identifies applicable CIMD/pre-registration fixtures and DCR-dependent exclusions. No hosted authorization server is included. |
| serve/inspect/diagram/docs/check/scenario/snapshot/diff commands | mcp/cli.rkt and command launcher; cli-artifacts plus existing command/scenario tests exercise actual command paths. |
| Scenarios and separate language extension | mcp/scenario*.rkt; examples/extensions/collection.rkt and related executable examples; native scenario controls and official Go collection probe. |
| Requirement-to-test ledger, pinned inputs and explicit refresh | IMPLEMENTATION.md, REMAINING.md, test-artifacts audits, vendor pins and scripts. Native runtime does not depend on Go/Node conformance tooling. |
| Reproducible source distribution and package verification | scripts/package.py and scripts/ci.py; final installed dependency checks and 22 installed cases pass on both versions in declared-build-20260908; archive comparison is recorded in release-package-20260908/reproducibility.json. |
| Linux 9.2/9.3 and native macOS/Windows | Final full checks pass: 6,264 native tests on 9.2 and 6,268 on 9.3, plus schema/regex/Scribble on both. GitHub native matrix is configured; final SDK commit run 34272422677 failed at startup with zero jobs (native-blocker-20260908). |

Only earlier-revision compatibility, other optional extensions, distributed stores,
and a hosted authorization service are excluded as originally approved. Deprecated
roots/sampling/logging/DCR are not advertised. Specification interpretations and
harness gaps are enumerated in conformance-closure-20260908/README.md.

Final release evidence closes every local row in REMAINING.md. Only native macOS/Windows verification remains, with the exact hosted pre-job failure retained. The guard regression was corrected without changing the existing adapter-view expectation; both final full commands exit zero.
