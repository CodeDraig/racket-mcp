# Implementation and evidence ledger

Target: MCP 2026-07-28; Racket 9.2. Evidence date: 2026-09-07.
**The requested seven-milestone release is incomplete.** This checkout contains a
working development implementation, not a release-level conformance claim.
Passing a fixture does not establish every behavior of an advertised facility.

## Milestones

| Milestone | Delivered | Remaining gate |
|---|---|---|
| 1. Foundation and vertical slice | Package, reader, ordinary Racket definitions, descriptors, local and stdio tools, pins | Source-aware declaration/workflow IR and five domain binding classes added; whole-interface reference analysis remains incomplete |
| 2. Schemas and declarations | Native schema evaluator; shapes; resources, prompts, completion; negative syntax tests | URI/pattern coverage, full durable embedding failure matrix |
| 3. Protocol SDK | Client/server stdio and HTTP JSON/SSE; discovery; header checks; subscription broker; authorization functions | Complete transport ownership, pagination policy, authorization flow integration, conformance coverage |
| 4. Durable interactions | SQLite stages, effects, MRTR, explicit recovery, task polling/update/cancel | Remaining workflow binding/extension checks, full task/effect/nested MRTR failure matrix |
| 5. Interface integration | Mounts/views, reference remapping, upstream domain adapters, cache/outbox primitives, separate extension example | Enforced effect restrictions, external freshness reconciliation, upstream MRTR/Tasks translation |
| 6. Developer experience | All named CLI commands have implementations; manifests, Scribble, examples | Complete manifests/diagrams/docs, scenario fault DSL, binding-aware extension API |
| 7. Release verification | Linux 9.2 tests, pinned schema suite, independent MCP checks, Go SDK probe, package checks | Full applicable conformance, other platforms/releases, all acceptance cases |

## Requirement-to-test ledger

“Covered” below means the named behavior has executed tests; it does not imply
complete coverage of its surrounding milestone.

| Requirement | Implementation and evidence | Status / limitation |
|---|---|---|
| Reader, module imports/exports, executable server, fragment | `mcp/lang.rkt`, `mcp/lang/reader.rkt`; `tests/core.rkt`, executable examples | Covered basic behavior and extension-generated server entry points |
| Required/optional/default arguments; omitted/null/false | `descriptor.rkt`, `forms.rkt`; `tests/core.rkt` | Covered defaults, order/count, distinct representations |
| Duplicate binders and resource-reference arity | `forms.rkt`, private resource binding; core/domain tests | Covered source-attached expansion errors; complete phase/hygiene matrix outstanding |
| Macro and data API share runtime values | `descriptor.rkt`, generated handlers; core/domain/upstream tests | Implemented; constructor checks are not yet fully equivalent for every declaration |
| syntax-spec-v3 | Private handler and domain binding interfaces | Schema/resource/operation/effect/workflow classes wired into declarations and stages; whole-interface reference analysis remains |
| Public extension API | `define-mcp-extension`, `examples/extensions/collection.rkt`, compiler tests | Distinct syntax-spec declaration/workflow extension classes and stage expansion implemented; full domain binding API remains open |
| Manifest without parent instantiation | Private collector/finalizer, `cli.rkt`; throwing parent fixture in compiler tests | Version 2 records local schemas, arguments, metadata, source locations, and normalized workflow stages; full capabilities and cross-module references remain incomplete |
| Exact JSON, bounds, duplicate keys | `json.rkt`; core/schema tests | Direct decoder now counts UTF-8 bytes and rejects malformed encodings; transports separately bound frames |
| JSON Schema 2020-12 core suite | `schema.rkt`, private pattern layer; `tests/schema-suite.rkt` | 1,301 pinned core cases passed; no failed/skipped core cases |
| References and annotations | Local registry, anchors, dynamic refs, unevaluated properties/items | Covered by official core cases, including local remote fixtures; no network fetching |
| Schema dialect/vocabulary rejection | Native evaluator and core tests | Pinned 2020-12 metaschema construction validation implemented; URI/pattern syntax coverage remains separate |
| Regex and optional format assertions | Private pattern compatibility layer | Partial; official optional cases not counted in the 1,301 result |
| Shapes and codecs | Generated constructor/accessors/JSON codecs; domain tests | Required fields and generated shape codecs implemented; checkpoint/effect codec registry and restart tests added |
| Resources, RFC 6570, links, embeds | `descriptor.rkt`, `uri-template.rkt`, `runtime.rkt`; domain tests and MCP fixtures | Text/binary and remapped reference identity covered; ambiguous URI overlap analysis incomplete |
| Prompts and completion | Runtime, composition, completion descriptors; domain and MCP fixtures | Wire strings and multi-content role lowering; renamed/removed completion targets covered; explicit string-codec syntax and JSON domain values implemented |
| Nested input-required rendering | `rendering.rkt`, tool/prompt dispatch; embedded-workflow tests | Persistent content layouts, child namespaces, source order and retained results implemented; nested text/JSON/binary presentations now supported; full crash/compatibility matrix remains open |
| Discovery and capability/version metadata | `runtime.rkt`; core and official stateless checks | Covered tested paths; no initialization/session state; complete facility-derived advertisement audit outstanding |
| JSON-RPC envelopes and errors | Runtime and transport modules; core and wire-schema checks | Tested envelopes and current error allocations; full notification direction and malformed-envelope matrix outstanding |
| Stdio concurrency/cancellation | `stdio.rkt`; core tests, official Go SDK probe | Bounded reader/workers/writer; EOF cleanup, client reader/port ownership, progress demultiplexing need more work |
| HTTP JSON/SSE and headers | `http.rkt`, `header-schema.rkt`; HTTP/header tests, independent scenarios | Tested versions/names/Unicode/annotated parameters and root URLs; Keep-alives, bounded decoded SSE events, and request cleanup implemented; Native bounded HTTP framing and TLS probes added; full disconnect/cancellation race matrix and timeout policy outstanding |
| Subscriptions | `subscription.rkt`; subscription tests and runtime integration | Ack order, filter routing, overflow, closure tested locally; full HTTP reconnect/filter-validation coverage missing |
| Pagination and caching fields | Runtime zero-TTL private results; upstream pagination | Cache fields pass fixtures; Opaque snapshot pagination and resource TTL declarations implemented; complete list caching and conformance matrix remain |
| Authorization | `authorization.rkt`; authorization/header tests | Verified principal, scope checks, issuer/resource-scoped OAuth helpers and PKCE; HTTP protected-resource metadata routes, 401/403 challenges, and shared runtime scopes implemented; explicit discovery/registration/browser/refresh/persistence orchestration and HTTP installation implemented; full metadata and provider conformance remain |
| Checkpoints and branches | `workflow.rkt`, generated explicit stages; workflow/branch tests | Sequencing, tail/non-tail if/match, and suspending let blocks covered by branch/control-flow tests; whole-interface reference analysis remains |
| MRTR state and input | Workflow/store and `interaction.rkt`; workflow and official MRTR fixtures | Opaque handles, ownership/arguments/expiry/code checks, sequential input; round-specific tokens, conflicting-response arbitration, and partial input batches covered |
| SQLite durability and recovery | `storage.rkt`, `workflow.rkt`; workflow/restart tests | Real child-process crash/manual recovery tested; full every-boundary concurrent/crash matrix missing |
| Effect policies | Transactional, idempotent, manual adapters; workflow/restart tests | Explicit intents and journaled recovery; instance claims exclude in-flight recovery; competing outcome repairs and retry waiting tested; exhaustive effect crash matrix remains |
| Workflow executable compatibility | Version and source-form fingerprint stored | Imported helper changes are not included in build fingerprint; complete executable compatibility gate missing |
| Tasks | `tasks.rkt`; tasks tests | Persist-before-return, polling, input update, owner checks, terminal immutability; task workers detached from request cancellation/output |
| Task restart and notifications | Runtime startup scan and exclusive worker claims; task-restart tests | Automatic working-task recovery, policy checks, and opted-in notifications implemented; notification replay is not provided; repaired failed task gets no automatic new handle |
| Interface views | `composition.rkt`; domain tests | Inclusion/exclusion/namespaces/names/URI mapping; completion and link names remap; additive scope requirements and versioned adapter replacements survive composition; enforced effect restrictions remain missing |
| Upstream adapters | `upstream.rkt`; upstream tests | Pinned snapshots and conservative discovery/declaration compatibility checks; tools, resources, templates, prompts, and completions forward through views; durable MRTR/Tasks translation remains missing |
| Freshness | `freshness.rkt`; freshness tests | Private cache and SQLite outbox primitives; Resource dependencies, acknowledged tool changes, runtime invalidation/publication, and explicit outbox hooks added; workflow completion/effect publication added; Opt-in ordinary resource caching and authorization-context partitioning added; external reconciliation and cross-principal policy remain |
| CLI and authored scenarios | `cli.rkt`; compiler tests, executable examples | Basic commands; scenarios run test submodules only; deterministic fault-injection scenario language missing |
| Documentation and package | Scribble manual; isolated package registration and setup | Linux build and package dependency checks passed; complete API reference and native platform checks outstanding |

## Initial independent validation (historical)

The counts and limitations in this section describe the initial implementation.
Later dated entries below supersede them; the latest native run has 1,567 checks,
1,301 pinned core schema cases, and five Go probes passing. Full release gates
remain open, including the explicitly recorded conformance discrepancies.

Pinned official inputs and per-file SHA-256 hashes are in `vendor/LOCK.json`.
The conformance harness and Go SDK are development dependencies; runtime modules
use Racket libraries. No compile-time network fetch occurs.

- `raco test tests`: 158 tests passed on the final native suite run.
- `racket tests/schema-suite.rkt`: 1,301 passed, zero failed or unsupported.
  This invokes the pinned draft2020-12 core files, not the optional directory.
- `raco make` and the Scribble HTML build passed.
- `raco setup --check-pkg-deps --pkgs racket-mcp` passed using the isolated package
  environment and clean distribution copy.
- The pinned official Go SDK passed stdio discovery, tools/list, and tools/call
  using protocol 2026-07-28. This is a three-operation interoperability probe.
- Official client `http-standard-headers`: 9 passed, 0 failed; two obsolete
  initialization checks skipped. `request-metadata`: 5 passed, 0 failed; three
  optional capability checks skipped. These are two scenarios, not all client
  conformance scenarios.
- Official server `--suite all --spec-version 2026-07-28`: the recorded run under
  `test-artifacts/conformance-release-check` had 136 passed and 7 failed checks
  across 40 scenarios. One fixture lacked a nonempty description and was
  corrected afterward; the targeted tools-list rerun passed all 4 checks under
  `test-artifacts/conformance-tools-list-fixed`. The six other failures remain.
  This is not a passing conformance release gate.
- All 858 vendored file hashes matched the recorded lock file.

The remaining scenario failures are explicitly classified:

| Scenario | Classification |
|---|---|
| tools-list | Empty fixture description; corrected, targeted rerun passed 4/4 |
| input-required-result-basic-sampling | Excluded: deprecated sampling is outside the approved release |
| input-required-result-basic-list-roots | Excluded: deprecated roots are outside the approved release |
| input-required-result-multiple-input-requests | Harness fixture requires sampling and roots as well as elicitation; excluded mixed-method fixture. Multiple elicitation requests now have native partial-response/restart coverage |
| input-required-result-capability-check | Harness specifically requests a sampling-only interaction; excluded fixture. Native missing-capability behavior is tested independently |
| input-required-result-multi-round | Completed in continuation: all 4 official checks pass in `test-artifacts/conformance-rounds` |
| input-required-result-non-tool-request | Prompt/resource workflow dispatch implemented; all 3 official checks passed in `test-artifacts/conformance-domain-workflows-fixed` |

All raw harness results remain in `test-artifacts`; failed runs are retained.
The server fixture uses the same public descriptors, macros, and runtime as an
application. No conformance-specific protocol branches are installed in the SDK.

## Reproduction commands

Run from the repository root:

```sh
. scripts/racket-env.sh
sh scripts/check.sh
GOCACHE="$PWD/.cache/go-build" GOMODCACHE="$PWD/.cache/go-mod" \
  go -C dev/interop run -mod=mod . "$PWD/examples/greeter.rkt"
python3 scripts/package.py
env -u PLTCOLLECTS raco setup --check-pkg-deps --pkgs racket-mcp
```

`check.sh` compiles modules, runs native tests and the schema runner, and builds
Scribble. Loopback HTTP tests require socket access. Package setup assumes the
isolated distribution link has been installed as documented in README.
`package.py` produces a source ZIP with sorted entries/fixed timestamps and a
SHA-256 file under `.cache/distribution`. It does not claim release readiness.

For the pinned upstream harness, install its locked development dependencies in
a separate working copy (`npm ci --ignore-scripts`). This run used
`/tmp/racket-mcp-conformance-20260907` after the first vendor-local npm extraction
failed. Run the server fixture in one terminal:

```sh
. scripts/racket-env.sh
racket -l mcp/cli -- --transport http --port 18765 \
  --state .cache/conformance.sqlite serve dev/conformance-server.rkt
```

Run the upstream harness with its `tsx src/index.ts server --url
http://127.0.0.1:18765/mcp --suite all --spec-version 2026-07-28 --output-dir ...`
command. Client scenarios use `client --command 'racket
/srv/data/code/racket-mcp/dev/conformance-client.rkt' --scenario
http-standard-headers` (or `request-metadata`) and the same version option.
Keep the checkout's Racket environment in the child process environment.

## Assumptions, trust, and interpretations

- The user-supplied plan remains the release contract. Missing items above are
  unfinished work, not a silently reduced scope.
- Defaults remain stdio, MRTR, explicitly configured durable paths, private
  zero-TTL cache hints, and no automatic retry of an uncertain initial mutation.
- Application definitions have ordinary Racket instantiation effects. Descriptor
  construction itself does not open application stores or start transports.
  Compiling third-party macros executes trusted Racket transformer code.
- Graceful subscription shutdown emits the dedicated completion result. Clients
  also accept the server cancellation notification described in cancellation
  prose. Full independent subscription interoperability remains unverified.
- SQLite is a one-host execution store. An idempotency key is not an exactly-once
  guarantee. Persistent state contains data, not Racket continuations or closures.
- Linux Racket 9.2 was executed. Native macOS, Windows, and another supported
  Racket release were unavailable and are unverified. At the initial validation,
  no Git repository existed and no commit or global package installation was
  performed. Git was subsequently initialized with a private GitHub remote;
  later entries record Git checks against that development checkout.

## Workflow control-flow continuation (2026-09-07)

Added private source-aware workflow nodes with checked control-flow destinations,
explicit transactional joins, non-tail conditionals/matches, and persistent lexical
`let` blocks. Compiler fingerprint prefix `mcp-workflow/2` rejects old saved
executions through the existing compatibility diagnostic. Imported helper code is
still not included in the fingerprint.

`tests/control-flow.rkt` exercises shadowing, simultaneous initializer scope,
left-to-right evaluation, database close/reopen between suspensions, branch joins,
terminal replay, duplicate binders, and hidden suspension rejection. These changes
do not complete the broader syntax-spec binding and language extension work.

Validation for this continuation: `sh scripts/check.sh` passed compilation,
168 native tests, all 1,301 pinned core schema cases, and the Scribble build.
`git diff --check` passed. No additional platform or independent conformance
claims are made by this control-flow change.

## Durable continuation rounds (2026-09-07)

SQLite now stores distinct random tokens per input stage. Tokens resolve to the
original principal/operation/arguments/version/expiry-bound workflow. Responses
are checked under the transition transaction, so concurrent conflicting responses
cannot overwrite an accepted value. Matching retries can retrieve later pending
input or the terminal outcome. Unknown response fields are ignored; a known input
from a different round is rejected. Tasks keep using their internal workflow handle.

The official `input-required-result-multi-round` scenario passed all 4 checks,
including wire schemas. New native tests cover token rotation, concurrent
conflicts, stale rounds, ownership, unknown tokens, and terminal replay.

Continuation validation: the full check script passed 180 native tests, 1,301
schema cases, compilation, and Scribble. After adding unknown-field handling,
the focused continuation suite passed 13 tests. The updated manual also built,
and `git diff --check` passed. Other release requirements remain open.

## Input batching (2026-09-07)

`await-input` accepts a batch of `[binder schema request-expression]` entries.
The generated `input-group` stage persists the request set and accepted individual
responses. Repeated requests list only missing inputs; request expressions do not
rerun after partial completion or reopening the database. Invalid responses and
conflicting replacements fail transactionally. The data API checks group value
identities and requires per-input response schemas. Capability preflight now
recognizes groups as elicitation stages.

`tests/input-groups.rkt` covers partial progress, invalid payloads, cancellation,
conflicting responses, SQLite reopen, and terminal replay. Nested resource/prompt
rendering and the general persistent codec registry remain unfinished.

Input-batch validation: `sh scripts/check.sh` passed compilation, all 192 native
tests, all 1,301 core schema cases, and the updated Scribble build.
`git diff --check` passed. This does not establish completion of nested MRTR.

## Prompt and resource workflows (2026-09-07)

Prompt/resource declarations now accept `#:workflow "version"` and compile through
the same source-aware workflow compiler as tools. The descriptor API accepts a
workflow descriptor separately from a normal handler. Serving any workflow now
requires explicit storage. Runtime capability checks precede execution, and each
resume runs authorization again. Persistent operation identity includes the MCP
method, preventing cross-method continuation reuse. Input-required outcomes pass
through without cache metadata; completed prompts/resources receive their normal
wire envelopes. Binary workflow result codecs and nested embedding remain open.

The new domain-workflow suite plus existing domain tests passed 26 checks.
The independent non-tool MRTR scenario passed all 3 checks after correcting the
fixture's schema to the harness's requested `context` field. The initial fixture
failure is retained. Dependent modules were rebuilt after descriptor shape changes.

Full validation for prompt/resource workflows: compilation, all 203 native tests,
all 1,301 core schema cases, Scribble, and `git diff --check` passed.

## Persistent embedded content (2026-09-07)

With storage configured, tool/prompt content positions capture embedded references
as a JSON layout before resolving children. The rendering engine saves the layout,
child continuation tokens and completed contents. Children resolve in source order;
input IDs include child and round namespaces. Retries do not reconstruct the parent
or rerun completed children, and current resource authorization is checked before
using retained content. Child workflow initial calls have stable internal invocation
keys for recovery after an uncertain child reply. Captured marker numbering resumes
after markers already stored by parent workflow stages.

`tests/embedded-workflows.rkt` passes 15 tests, including SQLite close/reopen between
children, two input-requiring children, parent evaluation count, retained results,
conflicting input, foreign principals, and changed resource authorization.
Nested resource presentation, full executable fingerprints for ordinary handlers,
and the complete cancellation/concurrent/crash-boundary matrix remain open.

Embedding validation: the full check script passed 218 native tests, 1,301
schema cases, compilation, and Scribble. A subsequently added regression for
markers spanning a workflow suspension passed with the 16-test focused embedding
suite. `git diff --check` passed. These are native behavioral tests; independent
nested-MRTR conformance has not yet been established.

## Resource presentations (2026-09-07)

Explicit `text-presentation`, `json-presentation`, and `binary-presentation`
constructors produce JSON-persistable resource values. Resources participate in
persistent embedding resolution, allowing prompt -> resource -> workflow-resource
input to resume through namespaced child requests. Text presentations combine
strings and embedded text; JSON receives application/json; binary values use blob
content without inventing a protocol content type. Nested rendering instances use
stable child invocation keys, and a repeated uncertain initial child request can
find the existing rendering before reconstructing its parent handler.

The presentation suite covers multi-level suspension/reopen, binary workflow
results, MIME labelling, JSON encoding, uncertain initial child reuse, and cycles.
Generic codec registration, renderer attachment declarations, and exhaustive
recovery/concurrency tests remain outstanding.

Presentation validation: `sh scripts/check.sh` passed compilation, all 229 native
tests, all 1,301 core schema cases, and Scribble. `git diff --check` passed.

## Persistent application codecs (2026-09-07)

Named/versioned value codecs define JSON schemas, pure decoders, and encoders.
Checkpoint/effect declarations can use a codec instead of a JSON schema. Values
are encoded before committing and decoded only through the executable's registered
codec when constructing a stage environment. Stored envelopes include identity
and version. Codec identities, versions, and schemas contribute to the workflow
fingerprint. Shapes generate a `Name-codec` binding alongside their conversions.
Manual effect recovery accepts an explicit codec registry and validates the encoded
observed outcome before advancing. No encoder/decoder procedures are persisted.

The codec tests cover shape round trips, conflicting/unregistered versions,
SQLite reopen, evaluation count, and manual effect recovery with/without the
required registry. Prompt string-codec declarations and complete build fingerprints
for imported executable helpers remain outstanding.


Codec validation: compilation, 241 native tests, 1,301 core schema cases, and
Scribble passed in the full check after codec-aware manual recovery was fixed.

## Task restart and worker ownership (2026-09-07)

Runtime construction now scans unexpired working tasks. Explicit deferred scanning
is available through `#:recover-tasks? #f` and `recover-runtime-tasks!`. Recovery
restores a principal through the application callback and rechecks identity,
verified-principal expiry, and tool authorization inside the worker claim. Missing
executables fail startup; incompatible workflow code follows the existing failure
channel. Awaiting-input and terminal tasks are not automatically executed.

Per-instance OS file locks plus process-local thread ownership prevent overlapping
task workers across SQLite connections and processes. SQLite stores create a sibling
`.workers` directory whose lock files must remain in place while runtimes are active.
The single-host implementation assumes one canonical database path, not hard-link
aliases or a network-shared database. Input updates wait for an existing worker to
release its claim, preventing a lost wakeup between publishing input_required and
releasing ownership. Startup scans skip claims still held by live workers.

Tests kill a real worker process inside an idempotent effect, prove another process
cannot enter the live effect, recover with the same recorded key after death, and
verify revoked authorization prevents further adapter execution. Native tests also
cover two store connections in one process, dead-thread claim cleanup, unsafe lock
identifiers, and input updates arriving before a prior claim is released. This does
not complete opted-in task notifications, manual recovery arbitration, or all crash
boundaries. Native macOS and Windows lock behavior remains unverified.

Task recovery validation: the full check script passed compilation, 263 native
checks, all 1,301 core schema cases, and Scribble. The focused task/restart/worker
suite passed 31 checks after task output isolation was added. The restart fixture
also emits an adapter diagnostic to verify it cannot corrupt protocol stdout.


## Opted-in Tasks notifications (2026-09-07)

`subscriptions/listen` now accepts the pinned extension's `taskIds` filter after
checking its shape, Tasks capability, per-task read authorization, and ownership.
Acknowledgement lists the accepted unique IDs. Committed task transitions publish
`notifications/tasks` containing DetailedTask fields on the subscription stream,
with its request ID. Identity keys isolate publications even when verified-principal
objects have changed between requests. Terminal no-op cancellation publishes nothing.

The runtime drops an obsolete pending publication if a newer revision committed
before enqueueing. Publication holds a read transaction through the bounded hub
enqueue so concurrent transitions cannot reorder old and new task snapshots.
These are optional runtime-local hints: reconnect/overflow requires tasks/get,
and cross-process notification fanout or durable replay is not claimed.

The stdio integration test exercises acknowledgement ordering, duplicate-ID
normalization, malformed/foreign filters, principal isolation, working/completed
transitions, subscription IDs, final result content, and terminal no-op behavior.
Emitted notifications are also checked against the pinned Tasks JSON Schema.

The pinned upstream `tasks-status-notifications` scenario is explicitly skipped
by its implementation pending a subscriptions/listen rewrite. Native stdio and
pinned-schema evidence above must not be represented as an independent harness
pass for that scenario.

Notification validation: the full check script passed compilation, 281 native
checks, all 1,301 core schema cases, and Scribble. After refreshing the working
transition timestamp and clearing obsolete input requests, the focused Tasks and
notification suite passed. `git diff --check` passed.


## Workflow execution and manual recovery arbitration (2026-09-07)

Workflow execution now holds an instance claim through external adapter invocation
and result persistence. SQLite stage transactions remain separate and short.
Concurrent calls wait cooperatively for the claim and then validate/read committed
state. Recovery attempts reject an active claim before changing any checkpoint,
effect intent, or journal entry. Two competing observed-outcome repairs cannot both
advance the same stage. After process/thread death, the lock mechanism permits the
existing effect policies to decide whether replay or manual intervention is legal.

The new recovery-races suite blocks a real manual adapter, attempts outcome/retry/
abandon recovery, checks unchanged state, starts a concurrent workflow retry, and
proves one adapter invocation with the same final result for both callers. It also
checks competing observed outcomes and a single recovery journal entry. The task
process-restart test now attempts direct recovery from another process while the
original workflow is inside its adapter. The complete every-boundary failure and
platform matrix remains outstanding.

Recovery arbitration validation: `sh scripts/check.sh` passed compilation,
298 native checks, all 1,301 core schema cases, and Scribble. The focused recovery,
codec, and process-restart suites passed before the broad run. `git diff --check`
passed. These results verify Linux single-host behavior; no additional native
platform or independent MCP conformance claim is made.


## Prompt string codecs (2026-09-07)

Prompt arguments accept `#:codec` with required, optional, and default forms.
Named/versioned string codecs convert the required wire strings to validated JSON
values; argument schemas add their own validation. Defaults run in declaration
order over earlier decoded values and bypass wire decoding. Missing/null/false
remain distinct. Codec expressions execute once during descriptor construction.
The ordinary API exposes `prompt-argument` and `encode-prompt-arguments`. Dynamic
prompt constructors reject duplicate names and directly declared non-string types
without a codec. Decode failures return invalid-parameters errors.

Codec identities, versions, and schemas contribute to durable prompt fingerprints.
SQLite reopen tests prove numeric domain values resume and version changes reject
old continuations. Tests also cover expression/default counts, optional values,
null/false wire encoding, malformed strings, invalid encoders, and equivalence of
macro-generated and dynamic descriptors. Arbitrary host structures are outside
this JSON-domain string-codec API; stage value codecs remain the explicit host
value persistence mechanism. Full imported-helper build fingerprints remain open.

Prompt codec validation: `sh scripts/check.sh` passed compilation, 317 native
checks, all 1,301 core schema cases, and Scribble. `git diff --check` passed.
These are native local-dispatch and persistence checks; independent prompt-codec
interoperability has not yet been run.


## Metaschema construction validation (2026-09-07)

Schema construction now runs the native evaluator against the pinned offline
2020-12 metaschemas. Runtime installation includes vendor/metaschemas; application
registries cannot replace these standard resources. Explicit custom dialects use
the preloaded registry and unknown required vocabularies fail during construction.
The bootstrap validation of trusted metaschemas avoids recursive self-checking.

A bounded JSON-value scan rejects cyclic structures, non-JSON host values, and
excessive schema depth/node counts before recursive evaluation. Structured schema
exceptions retain child diagnostics from failed composition. Property, applicator,
dependent-schema, and tuple-item paths now use proper JSON Pointer segments rather
than escaping a combined path as one key.

Construction tests cover required/dependentRequired uniqueness, keyword types,
empty applicators, anchor names, nonempty ID fragments, annotation/content types,
nested errors, registry overrides, unknown vocabularies, cycles, non-JSON values,
limits, and diagnostic pointers. Format annotations do not assert URI or regex
validity: complete URI/pattern compatibility remains a separate open gate.

Metaschema validation: `sh scripts/check.sh` passed compilation, 348 native
checks, all 1,301 pinned core schema cases, and Scribble. `git diff --check`
passed. The official suite includes custom-vocabulary and locally registered
reference cases; optional format/regex suites remain outside this count.

Regenerated the source distribution and passed isolated
`raco setup --check-pkg-deps --pkgs racket-mcp`. With PLTCOLLECTS unset, module
resolution selected `.cache/distribution/racket-mcp/mcp/schema.rkt`; an installed
runtime probe accepted a valid string schema and rejected duplicate required names
through `exn:fail:schema`. This verifies packaged offline metaschema availability.


## Resource renderer attachments (2026-09-07)

Resources accept `#:render` through both declarations and `make-resource`.
Named/versioned text, JSON, and binary renderer constructors advertise a MIME type
and convert domain values to explicit presentations. Conflicting resource MIME
metadata and invalid renderer procedures fail construction. Ordinary handlers can
return host shape instances, which render before any persistent layout is saved.
Workflow completion values retain their existing persistability requirements.

Renderer execution participates in ordered persistent embedding. A renderer that
embeds an input-requiring child resumes from the saved layout without rerunning
the parent handler or renderer. Its identity/version/MIME type contribute to both
rendering and direct resource-workflow continuation fingerprints. Full imported
helper fingerprints remain open, so authors must version changed renderers.

Tests cover descriptor-expression count, host shape rendering, SQLite reopen,
nested input requests, retained parent/renderer work, JSON and binary output,
MIME declarations, invalid procedures, and renderer-version mismatch for both
rendering and direct workflow continuations.

Renderer validation: `sh scripts/check.sh` passed compilation, 363 native checks,
all 1,301 core schema cases, and Scribble. `git diff --check` passed. Independent
renderer interoperability and the complete composition/manifest gates remain open.


## Checked declaration and workflow extensions (2026-09-07)

`define-mcp-extension` now selects declaration or workflow extension kinds,
backed by distinct private syntax-spec-v3 extension classes and nonterminal
expanders. Declaration remains the default and supports ordinary module helpers
plus core declarations. Workflow extensions expand at stage boundaries into the
same checked private workflow IR; host expressions are not expanded by that pass.
Using a workflow extension inside a host expression is rejected by its class.
Extensions use lexical module bindings rather than a registration table.

The separately compiled approval extension demonstrates an elicitation stage.
Tests cover renamed imports, suspension/resume, host-name shadowing, declaration
extension output, invalid generated binders, and invalid host placement. Existing
collection extension and manifest tests still pass. Every language module now
has the serving entry point, which checks the collected interface for a server;
this supports extension-generated servers and diagnoses directly executed fragments.
A subprocess test invokes a generated server over stdio and checks its tool reply.

Normalized emitted stages now contribute to workflow fingerprints, including
extension output absent from caller source. This changes the compiler version to
mcp-workflow/3; incompatible old state fails the existing compatibility gate.
Complete domain binding classes, declaration IR/reference checks, and imported
runtime helper fingerprints remain outstanding.

Extension validation: `sh scripts/check.sh` passed compilation, 374 native
checks, all 1,301 core schema cases, and Scribble. `git diff --check` passed.
The generated-server subprocess test provides native stdio evidence; independent
extension-generated interface interoperability has not yet been run.


## Domain binding classes (2026-09-07)

Schema, operation, resource, effect, and workflow-value classes now use private
syntax-spec-v3 definition/expression interfaces. Schema primitives and schema/shape
forms establish schema bindings; tool/prompt/workflow forms establish operation
bindings. Resources retain their source-checked arity facade over a resource-class
binding. Workflow stage environments use workflow-value bindings and retain local
Racket mutation. Effect adapters bind in a distinct namespace and keep their lexical
syntax in workflow IR until emission, without capturing host variables.

Known operation/resource names used directly as schemas now fail expansion.
Ordinary computed schema expressions retain runtime validation. Conflicting effect
policies fail statically and in the dynamic workflow constructor. Module declaration
identifiers are immutable; ordinary Racket definitions retain their semantics.
Top-level/REPL declarations fall back to ordinary definitions because the framework's
checked definition interface requires module/internal-definition context.

Tests cover renamed imports, dynamic-require, cross-phase schema values, class
mismatches, dynamic host schemas, resource arity behavior, effect/host name collisions,
workflow-local mutation, and matching static/dynamic effect-policy diagnostics.
Whole-interface reference analysis and the source-aware declaration IR remain open.

Domain binding validation: `sh scripts/check.sh` passed compilation, 394 native
checks, all 1,301 core schema cases, and Scribble. `git diff --check` passed.
This establishes the tested lexical/phase/runtime behavior, not completion of the
whole-interface compiler or release conformance gates.


## Source-aware declaration manifests (2026-09-07)

The module collector now retains lexical declaration names, source syntax,
argument syntax, clauses, and workflow summaries in a private declaration IR.
Finalization emits manifest version 2 without executing application expressions.
Primitive schemas and same-module schema aliases/shapes resolve statically;
computed/imported schemas are explicitly unknown. Default expressions remain
unevaluated. Tool argument contracts lower into input schemas when resolvable.
Static resource URI collisions and direct schema-alias cycles fail expansion.

Tool, prompt, and resource workflows expose normalized stages with source
locations, schemas, effect policies, and adapter/branch identities. Their storage
requirement is explicit; adapter requirements appear only for effect stages.
Server metadata registers at the module declaration boundary, avoiding loss when
descriptor construction expands within an expression. Runtime descriptor creation
and application module-instantiation semantics remain unchanged.

The throwing-parent fixture verifies inspection without application or metadata
execution, resolved schema contracts, dynamic-value markers, source spans,
resource collisions, and stage summaries for all three workflow declaration kinds.
Cross-module static contracts, complete reference analysis, and full capability
manifests remain unfinished.

Declaration-manifest validation: `sh scripts/check.sh` passed compilation,
416 native checks, all 1,301 pinned core schema cases, and Scribble. CLI inspection
of the throwing-parent fixture produced a readable eight-declaration manifest;
a separate expansion probe rejected a cyclic schema alias. `git diff --check`
passed. Independent conformance and platform checks were not rerun for this change.


## Request-scoped SSE bounds and ownership (2026-09-07)

A private incremental SSE reader bounds event accumulation before JSON decoding,
handles CR/LF/CRLF packet boundaries, BOMs, multiline data, comments, and the
single-space field rule. HTTP clients reject malformed SSE envelopes, unrelated
response IDs, and independent server requests. Configurable response limits bound
JSON bodies and decoded SSE events. Completed readers now shut down their whole
request custodian, including net/http-client response-copy workers and sockets.

Server SSE uses one writer and a bounded 64-event queue, periodic configurable
keep-alive comments, and X-Accel-Buffering: no. Output failure signals cooperative
cancellation, waits up to 200 ms, then shuts down request-owned resources. Durable
task ownership remains separate. Unexpected request-worker exit terminates the
stream rather than emitting keep-alives indefinitely.

Native tests cover partial framing, oversized unterminated/multiline/Unicode
input, comments, malformed UTF-8, response identity/direction, real TCP socket
closure on successful and failed reads, and disconnect cleanup for an application
handler that ignores cancellation. Closing a net/http-client response port alone
did not close its socket in the probe; ownership tests therefore close the actual
connection custodian.

Limits are not yet an end-to-end wire memory bound: net/http-client chunk and
response-header parsing occurs before the new SSE reader and needs separate
bounding. Full subscription/disconnect race and platform coverage remain open.

SSE continuation validation: `sh scripts/check.sh` passed compilation, 443 native
checks, all 1,301 pinned core schema cases, and Scribble. The focused live HTTP
stream suite also passed all 14 checks. `git diff --check` passed. Independent
conformance and native macOS/Windows verification were not rerun in this slice.


## Native bounded HTTP framing (2026-09-07)

The HTTP client now uses a private native HTTP/1.1 reader rather than the generic
library chunk decoder. Response data flows through an 8 KiB copy buffer and a
64 KiB pipe; neither chunk size nor Content-Length controls allocation size.
Aggregate informational/final headers use a configurable byte budget (64 KiB by
default), chunk framing lines use 8 KiB, and trailers use the header budget.
Conflicting lengths, length/transfer ambiguity, malformed framing, and truncated
bodies fail. Unknown compressed content is rejected after requesting identity
encoding. URLs require HTTP(S) without user information. HTTPS uses the secure
Racket OpenSSL context, including certificate and hostname verification. Automatic
redirects and POST replay are not introduced.

Tests include a huge declared chunk that delivers a small final SSE response
without completing that chunk, oversized unterminated framing, truncation,
informational responses, duplicate matching lengths, trailers, and ambiguous
framing. Existing real-socket cleanup and HTTP tests still pass. The separate
local TLS probe uses an ephemeral certificate and verifies accepted trust plus
rejection of hostname mismatch and absent trust. No test certificate/key is part
of the source distribution.

Validation: `sh scripts/check.sh` passed compilation, 458 native checks, all 1,301
pinned schema cases, and Scribble. The pinned official client HTTP header scenario
passed 9/9 applicable checks (2 obsolete initialization checks skipped), with
artifacts under `test-artifacts/conformance-native-http-headers`. A live HTTPS GET
returned HTTP 308 without following it. `dev/tls-probe.rkt` passed its 3 checks via
`raco test ++arg /absolute/cert.pem ++arg /absolute/key.pem dev/tls-probe.rkt`.
`git diff --check` passed. Timeout policy, full transport race/conformance coverage,
and native platform coverage remain open.

Framing reference: https://www.rfc-editor.org/rfc/rfc9112.html . TLS reference:
https://docs.racket-lang.org/openssl/index.html .


## Strict UTF-8 and schema work budgets (2026-09-07)

Direct JSON decoding now counts consumed UTF-8 bytes and validates byte sequences
before decoding rather than accepting replacement characters from read-char.
Lookahead is bounded to four bytes and preserves the next value's port position.
A known oversized code point fails without waiting for absent continuation bytes.
Whole-string decoding permits only the four JSON whitespace characters after the
value. Tests distinguish valid U+FFFD from malformed wire encodings and exercise
exact byte boundaries and fragmented input.

Schema validation accepts a max-steps budget shared by nested metaschema checks,
registry indexing, applicator visits, and property/item traversal. Budget exhaustion
raises rather than becoming permissive. Cyclic registry values fail explicitly.
Prefix-item indexing uses a vector so repeated list scans do not introduce a
quadratic path. Counted structural work is bounded; regex CPU and arbitrary large
numeric-operation costs are not claimed to be bounded by this counter.

Regressions include a compact reference graph with exponential applicator visits,
low/high budget outcomes, fresh budgets after failure, and cyclic registry inputs.


JSON/budget validation: `sh scripts/check.sh` passed compilation, 488 native
checks, all 1,301 pinned core schema cases, and Scribble. `git diff --check`
passed. No new independent protocol or platform conformance claim is made by
these decoder and validator changes.


## Declared dependencies and acknowledged changes (2026-09-07)

Resource descriptors and forms accept depends-on callbacks over bound arguments.
Ordinary tool descriptors and forms accept changes callbacks with an explicit
committed-outcome binder. committed-result acknowledges the mutation commit;
plain success and execution-error results do not trigger changes. Its explicit
keys and the declared keys combine before runtime invalidation/publication.
Notifications follow acknowledged commits even if subsequent rendering suspends.

Each runtime owns an injectable resource cache. runtime-report-change! invalidates
principal-partitioned entries before notifying matching resource subscriptions,
using mounted URI matchers and declared dependency keys. Read authorization and
principal expiry are rechecked at delivery. Authorization callbacks run outside
the subscription lock. SQLite runtimes append outbox entries before publication;
external reports and explicit transactional outbox draining use the same path.

Cache loading no longer executes application computation under its lock. An
invalidation generation prevents a concurrent stale insertion. Entry count is
bounded (default 1024). Positive-TTL resource read integration and complete
authorization-context cache keys remain open. Workflow changes and external
adapter reconciliation are not claimed complete by this ordinary-tool path.

Tests cover failed/unconfirmed mutation outcomes, mounted resource updates,
cache invalidation before notification, principal isolation, transactional rollback,
read-policy changes, reentrant cache loading, and invalidation during a load.

Freshness continuation validation: `sh scripts/check.sh` passed compilation,
509 native checks, all 1,301 pinned core schema cases, and Scribble. The added
freshness documentation then built after assigning an explicit short section tag.
`git diff --check` passed. Independent freshness interoperability and the remaining
workflow/cache integration gates have not been established by this continuation.


## Durable workflow change publication (2026-09-07)

Workflow descriptors and forms now accept completion changes over original bound
arguments and the completed result. The outbox entry and terminal result commit
in one transaction; terminal retries do not reevaluate the change declaration.
Execution-error completions skip it. Effect adapters can acknowledge immediate
changes with committed-result: the ordinary result passes through its codec/schema
and keys enter the outbox with the stage transition. Transactional application
writes share that transaction. Manual outcome recovery accepts acknowledged keys.
The workflow journal records the stage and outbox handle for each change batch.

Runtime workflow and task workers attempt outbox publication after committed
stages, including before subsequent input boundaries. Publication failures leave
pending entries and do not turn committed outcomes into execution failures. Direct
workflow callers can drain explicitly. Workflow execution rejects an enclosing
transaction on the same store so it owns the actual commit boundaries.

New tests cover SQLite reopen, concurrent terminal retries, publication failure,
transactional mutation rollback, manual repair keys, error completions, and task
notifications before input and after completion. The tests do not establish the
entire process-crash/external-reconciliation matrix. Positive-TTL resource caching
and full authorization-context cache keys remain unfinished.

Durable-change validation: `sh scripts/check.sh` passed compilation, 539 native
checks, all 1,301 pinned core schema cases, and the updated Scribble manual.
`git diff --check` passed. A journal serialization defect found during integration
was corrected before this full run. Independent freshness interoperability and
native platform coverage were not added by this continuation.


## Opt-in resource caching (2026-09-07)

Resource descriptors and forms accept ttl-ms, defaulting to zero. Ordinary
successful reads can reuse complete snapshots. Durable workflow/continuation and
invocation-state requests bypass caching; input-required results are not cached.
Snapshots retain transitive resource URI authorization checks and dependency keys.
A parent inherits its earliest child expiry, and hits return remaining TTL rather
than renewing it. Verified-principal expiry also bounds the TTL and expired
principals are rejected before dispatch.

Partitions include runtime namespace, owner, effective authority, capabilities,
bound arguments, and dependency keys. Verified claims form the default authority
key; applications can supply a stable immutable cache-context policy key. Shared
cache instances cannot mix output across runtime namespaces. Committed changes
invalidate all authority variants belonging to the owner, including parent
snapshots dependent on a changed child. A cache invalidation during computation
prevents insertion and sets the returned snapshot TTL to zero.

Tests exercise hits/expiry, elapsed child TTL during parent rendering, changed
scopes and policy versions, transitive authorization revocation, principal expiry,
owner-wide invalidation, and concurrent invalidation before insertion. Broader
cross-principal change policies and the complete caching conformance matrix remain
open; no durable continuation caching is advertised.

Resource-cache validation: `sh scripts/check.sh` passed compilation, 554 native
checks, all 1,301 pinned core schema cases, and Scribble. The updated caching
reference also built separately. `git diff --check` passed. Independent caching
interoperability and native platform verification were not added in this slice.


## Bound opaque pagination (2026-09-07)

All four list methods now paginate with runtime-configurable page size, cursor
lifetime, token count, and encoded-data retention limits. The first page freezes
wire metadata; repeated cursors return stable pages and next cursors. Bindings
include method, owner, authority context, capabilities, and non-cursor parameters.
Per-request authorization still precedes lookup. Invalid, expired, or unrelated
cursors use -32602. Capacity eviction removes complete snapshots, and oversized
listings fail explicitly. Runtime restarts invalidate these ephemeral cursors.
Pages retain zero TTL and private cache scope.

Native tests cover all list methods, page order, retries, expiry, empty/null/foreign
cursors, changed scopes/parameters, capacity eviction, and mutable descriptor
metadata after the first page. A separate Go SDK fixture follows the actual
returned cursors over stdio. The upstream pinned harness has no separately named
pagination fixture in its vendored file inventory; this does not substitute for
the broader applicable conformance suite.

Pagination validation: `sh scripts/check.sh` passed compilation, 601 native
checks, all 1,301 pinned core schema cases, and Scribble. The pagination fixture
compiled and the updated manual built separately. The pinned official Go SDK
retrieved three pages containing five ordered tools via returned opaque cursors.
`git diff --check` passed. Broader list-cache conformance and platform coverage
remain open.

## Stdio lifecycle and progress routing (2026-09-07)

The stdio client tracks progress tokens independently from JSON-RPC request IDs.
Tokens must be strings or integers and unique among active requests; completion
releases them. Progress notifications reach the owning handle without completing
it. Completed handles ignore cancellation. Responses and notifications pass
basic envelope validation before dispatch, and malformed messages fail pending
requests rather than being returned as successful protocol outcomes.

Clients own their input/output ports by default. Explicit close, EOF, and reader
failure resolve pending requests and clean up the reader and both owned ports.
Applications retaining ports use close-ports? false. State and writer locks are
separate so a blocked output peer does not prevent close from resolving requests.
Server EOF and exceptional reader exit signal request cancellation, wait one
shared 200 ms grace period, and shut down request custodians. Runtime-owned tasks
remain outside those custodians.

The new lifecycle tests cover concurrent token routing, integer zero, duplicate
and invalid tokens, token reuse, pending-handle EOF resolution, retained terminal
results, borrowed ports, malformed envelopes, a blocked writer, and a handler
that ignores cancellation during EOF shutdown. Full notification direction and
progress-value validation, isolated subscription overflow, and the broader
transport race matrix remain open.

Stdio continuation validation: `sh scripts/check.sh` passed compilation, 628
native checks, all 1,301 pinned core schema cases, and Scribble. The official Go
SDK discovery/list/call probe passed against the updated stdio server. Initial
focused execution identified stale compiled dependents; the full check rebuilt
them before the passing run. `git diff --check` passed. This does not establish
full protocol or native platform conformance.

## Isolated stdio notification overflow (2026-09-07)

Each stdio request notification channel has a configurable positive capacity
(notification-limit, default 64). Overflow resolves only that handle with the
public exn:fail:notification-overflow exception carrying its request ID. A separate
control worker sends cancellation without blocking the reader, allowing other
responses and subscriptions to continue. Late responses cannot replace the local
failure. Progress tokens remain reserved after local overflow until the remote
terminal response or cancellation arrives, preventing late updates from reaching
a replacement request using the same token.

The control queue is independently bounded at 64 entries; exhaustion is an
explicit connection-level failure. Client cleanup stops both reader and control
worker, including when ports are borrowed. Tests cover concurrent subscription
and ordinary-request survival, emitted cancellation, re-listening, ignored late
traffic, token reservation/release, and terminal-result preservation. HTTP clients
have per-request streams; the complete cross-transport overflow/filter matrix
remains a separate release gate.

Overflow continuation validation: focused stdio/lifecycle/subscription tests passed
47 checks. `sh scripts/check.sh` then passed compilation, 643 native checks, all
1,301 pinned core schema cases, and Scribble. `git diff --check` passed. No new
independent interoperability or platform claim is made by this continuation.

## Subscription acknowledgement without shared I/O locks (2026-09-07)

Listeners register under the hub lock, then send their acknowledgement outside it.
Changes arriving during acknowledgement queue in the listener's bounded channel;
only that listener drains the channel, after acknowledgement returns. A blocked
transport acknowledgement therefore cannot hold up another listener's registration
or change publication. Failed acknowledgements deregister through dynamic-wind,
including arbitrary raised Racket values. Hub operations prune forcibly terminated
listener threads, whose termination may bypass dynamic-wind cleanup.

Closure and overflow take priority over buffered events. If acknowledgement was
blocked long enough to overflow, the listener acknowledges and then returns the
overflow error without draining the stale queue. Tests exercise blocked-I/O
isolation, retained changes during acknowledgement, per-listener ordering,
overflow isolation, graceful closure, acknowledgement failure, and forced thread
termination. The full independent subscription/filter/transport matrix remains
open.

Acknowledgement continuation validation: focused subscription/freshness/task
notification tests passed 66 checks before adding the retained-queue regression.
`sh scripts/check.sh` then passed compilation, 673 native checks, all 1,301 pinned
core schema cases, and Scribble. `git diff --check` passed. No new independent
subscription interoperability or native platform verification was performed.

## Protected HTTP resource metadata and shared scope policy (2026-09-07)

Runtime construction accepts a required-scopes callback over method/parameters.
Its validated OAuth scope tokens combine with the existing authorization callback,
so local dispatch, embedded reads, notification authorization, and resumed workers
use the same scope policy. HTTP checks required scopes before opening SSE and
returns 403 with an insufficient_scope challenge rather than executing the handler.
Policy callbacks can run more than once and are documented as pure.

HTTP handler/server constructors accept resource-metadata and an optional explicit
resource-metadata-url. Otherwise the URL is derived from the external HTTPS
resource identity and its endpoint path. The metadata route serves public GET
with CORS access. Protected configuration requires an explicit authentication
adapter, verifies returned principal issuer/audience/expiry against the metadata,
and includes the metadata URL in 401 challenges. Scope-token validation prevents
invalid header values, and metadata construction rejects an empty issuer list.
This configuration supports an external HTTPS identity behind a TLS-terminating
proxy; the live tests use local HTTP transport with that explicit deployment model.

New real-socket tests cover public metadata discovery, invalid/absent credentials,
expired principals, insufficient scopes before SSE/handler execution, authorized
SSE calls, local-dispatch equivalence, metadata URL construction, and scope header
validation. Full OAuth client discovery fallback, challenge parsing, browser and
credential integration, and independent authorization conformance remain open.

Protected-resource continuation validation: focused authorization and HTTP tests
passed 49 checks. `sh scripts/check.sh` then passed compilation, 702 native checks,
all 1,301 pinned core schema cases, and Scribble. Root and path-specific metadata
URL construction were exercised. `git diff --check` passed. No new independent
OAuth interoperability or native platform verification is claimed.

## Resource-bound authorization discovery fallbacks (2026-09-07)

The client discovery API now tries protected-resource metadata at the endpoint's
well-known path and then the origin root. An explicitly supplied metadata URL
(e.g. from an authentication challenge) takes precedence without a silent fallback
to another document. Exact resource identity is checked, including any query in
the resource identifier; discovery URLs themselves omit that query.

Authorization metadata uses the required OAuth insertion/OIDC insertion/OIDC
appending order, with two candidates for root issuers and three for path-bearing
issuers. URL construction preserves ports and IPv6 authorities. Issuer selection
is an application callback restricted to advertised issuers. Retrieved metadata
must identify that exact issuer, advertise the code response type, and provide
HTTPS authorization/token endpoints. Only the fetch adapter's explicit #f outcome
permits fallback; exceptions and invalid or mismatched documents stop discovery.

Tests cover candidate order, early success, explicit URL precedence, resource and
issuer mismatch, arbitrary fetch failure, endpoint selection, response-type
requirements, query-bearing resource identities, and IPv6 construction. Native
HTTP discovery fetch integration, challenge parsing, full OIDC-specific metadata
validation, registration selection, and credential-flow orchestration remain open.

Discovery continuation validation: focused authorization tests passed 57 checks.
`sh scripts/check.sh` passed compilation, 722 native checks, all 1,301 pinned core
schema cases, and Scribble. `git diff --check` passed. Discovery tests use explicit
fixture fetch adapters; no live authorization-provider interoperability is claimed.

## Authentication challenge parsing and HTTP outcomes (2026-09-07)

A native WWW-Authenticate parser handles combined/repeated fields, multiple
schemes, token68 credentials, case-insensitive parameter names, token and quoted
values, escaped quotes, and commas inside quoted values. Duplicate parameters,
malformed syntax, and control characters fail. Aggregate bytes default to 64 KiB,
with at most 64 parameters per challenge. The implementation follows the grammar
and list behavior in RFC 9110 sections 11.2, 11.3, and 11.6.1:
https://www.rfc-editor.org/rfc/rfc9110.html#section-11.3 .

HTTP 401/403 now produce exn:fail:http:authorization, retaining status, raw headers,
bounded body bytes, and parsed challenges. Empty or non-JSON bodies no longer
lose the authorization outcome to a JSON decoding error. Low-level handles yield
the exception; synchronous calls raise it. The client does not authorize, open a
browser, or replay a request automatically. Native discovery fetches and the
higher-level credential-flow orchestration remain open.

Tests cover the RFC multi-scheme example, quoted comma/escape handling, token68,
combined fields, duplicate/malformed parameters, byte limits, and real HTTP
401/403 outcomes with preserved metadata and scope-error bodies. A dynamic-regex
escaping defect found by the initial focused run was corrected before rerunning.

Challenge continuation validation: the corrected focused run passed 80 checks.
`sh scripts/check.sh` passed compilation, 747 native checks, all 1,301 pinned core
schema cases, and Scribble. `git diff --check` passed. No new live authorization
provider, independent conformance, or native platform claim is made.

## Native OAuth HTTP adapters (2026-09-07)

The new mcp/oauth-http library returns metadata-fetch and token-exchange callbacks
for the existing discovery/PKCE/refresh APIs. Requests use the native bounded HTTP
framing reader, verified HTTPS, GET metadata and form-encoded POST token fields.
Metadata GET 404/405 returns #f for explicit discovery fallback; other non-200
responses raise exn:fail:oauth-http retaining status, headers, and body bytes.
Successful responses require application/json objects. No credentials are added
to metadata fetches, and neither redirects nor retries happen automatically.

Each request owns its worker, sockets, and copy worker through a custodian.
Configurable defaults are 30 seconds, 1 MiB response data, and 64 KiB headers.
Timeout and caller exception/break unwinding shut down the request resources.
HTTPS is required by default; a separately enabled literal-loopback HTTP option
supports local development fixtures without changing discovery identifier rules.

Real-socket tests cover metadata and token requests, UTF-8/form escaping,
unavailable-document responses, retained HTTP errors, redirect rejection,
response-size limits before a huge declared body finishes, content-type rejection,
timeout socket cleanup, and caller interruption. Higher-level registration,
credential persistence, browser interaction, refresh coordination, and explicit
challenge-to-discovery orchestration remain open.

Native OAuth HTTP validation: the initial focused socket run passed 29 checks;
the caller-interruption regression was included in the full run. `sh scripts/check.sh`
passed compilation, 779 native checks, all 1,301 pinned core schema cases, and
Scribble. A duplicate module-index warning was corrected by separating the new
manual section; the manual rebuilt without that warning. `git diff --check`
passed. The new adapter tests use explicitly enabled loopback HTTP; live provider
OAuth interoperability and native platform verification remain unestablished.

## Issuer-scoped registration selection and client metadata (2026-09-07)

Client ID Metadata Document construction and validation now enforce exact hosting
URL identity, HTTPS/path requirements, absence of literal/encoded dot segments,
client name and redirect lists, and prohibition of shared-secret fields. The
supported token authentication method is public-client none; private_key_jwt is
not implemented. Applications retain responsibility for hosting the generated
JSON. Constraints follow the draft explicitly referenced by the pinned MCP prose:
https://www.ietf.org/archive/id/draft-ietf-oauth-client-id-metadata-document-00.html .

Registration selection prefers a pre-registered entry keyed by exact issuer,
checks its embedded issuer/client ID/redirect, and uses the current request's
resource and scopes. Otherwise advertised CIMD support permits an explicitly
supplied document and URL, with an exact listed redirect. An optional application
callback can supply manual registration if neither path applies. Entries for
other issuers are never used. No dynamic registration or automatic publishing is
introduced. Direct begin-authorization calls now validate issuer/resource,
redirect, scopes, and client ID before constructing PKCE requests.

Tests cover metadata identity/path/secret restrictions, pre-registration
precedence, issuer changes, redirect mismatches, manual selection, and current
resource/scope binding. Complete browser/credential-flow orchestration and live
provider interoperability remain open.

Registration continuation validation: focused authorization/registration checks
passed 59 tests. `sh scripts/check.sh` passed compilation, 810 native checks,
all 1,301 pinned core schema cases, and Scribble. `git diff --check` passed.
These are authored metadata and selection tests, not hosted-document or live
provider interoperability evidence.

## Explicit authorization and credential runner (2026-09-07)

The new mcp/oauth authorizer connects resource-bound discovery, issuer-scoped
registration selection, PKCE/browser callbacks, token exchange, refresh, and
credential persistence callbacks. Native HTTP adapters are defaults. The runner
returns a credential and never issues or retries the triggering MCP operation.
Challenge scopes take precedence; explicit scopes or protected-resource defaults
apply otherwise. Multiple Bearer challenges require explicit caller selection.

Credentials use issuer/client-ID/resource keys, and one authorizer serializes its
flows. Suitable unexpired credentials are reused; expired/rejected credentials
can refresh within their previous grant. Scope step-up uses a fresh browser flow.
The rejected-token argument prevents a stale concurrent challenge from rejecting
a newer token. Failed exchanges require explicit reauthorization. Successful
exchanges survive transient save failure in memory, allowing persistence-only
retry without repeating the consumed code/refresh token. This in-memory state is
not durable recovery after process loss; persistence callbacks must handle their
storage's uncertainty and cross-process coordination.

Token responses now validate bearer token syntax, expiry, refresh token and scopes.
Omitted refresh-response scopes retain the previous granted scopes instead of
newly requested permissions. Empty scope requests omit the query parameter, and
empty authorization codes fail before exchange. Tests cover reuse, concurrent
refresh, scope step-up, issuer change, persistence retry, uncertain exchange,
foreign loaded credentials, malformed token responses and refresh grant retention.
Full transport convenience integration, live provider interoperability, and the
remaining metadata validation/conformance gates are still open.

Authorization-runner validation: focused flow/token checks passed 54 tests, and
the strengthened empty-code assertion passed its 13-test token suite. The full
`sh scripts/check.sh` passed compilation, 864 native checks, all 1,301 pinned core
schema cases, and Scribble. `git diff --check` passed. Browser/token/persistence
callbacks in these flow tests are deterministic fixtures; live-provider and
cross-process credential-store behavior were not established.

## Explicit HTTP credential installation (2026-09-07)

The new mcp/oauth-http-client helper connects HTTP authentication outcomes to the
authorization runner and installs the returned token without replaying an MCP
operation. Client URL, authorizer resource, and failed request resource must match
exactly. HTTP requests snapshot URL and token before worker startup; structured
401/403 failures retain that request identity. The rejected token therefore comes
from the failed request, not a possibly newer mutable client token.

Delayed insufficient-scope challenges now reuse a newer credential when it covers
the requested scope. Before installation, the helper rechecks the endpoint and
current token to detect changes made during application callbacks. It refuses
cross-resource installation or overwriting a different newly installed token.
HTTP client construction rejects URL fragments. The exception's retained request
token is documented as credential data and is absent from its message text.

Tests cover initial installation, rejected-token refresh, stale token/scope
challenges, cross-resource failures, callback URL/token changes, and real HTTP
failure request-identity fields. Provider interoperability, complete metadata
validation, and remaining transport cancellation/timeout races remain open.

HTTP authorization integration validation: focused HTTP/runner checks passed 97
tests. `sh scripts/check.sh` passed compilation, 883 native checks, all 1,301 pinned
core schema cases, and Scribble. `git diff --check` passed. Integration uses
explicit deterministic authorization callbacks plus local HTTP failure fixtures;
no live provider or native platform conformance claim is made.

## Authorization metadata profile validation (2026-09-07)

Discovery now retains endpoint provenance when selecting OAuth versus OIDC
metadata validation. Both paths validate exact issuer, HTTPS operational URLs,
authorization-code support, known list/boolean fields, and JWT client-authentication
algorithm declarations. OIDC fallback documents additionally require jwks_uri,
subject_types_supported, and RS256 in id_token_signing_alg_values_supported.
Invalid documents fail immediately rather than being bypassed through another
fallback URL. The public validation function permits direct metadata checks.

Tests distinguish minimal OAuth documents from OIDC documents, cover missing
required fields and malformed optional values, reject unsupported grants and
invalid JWT authentication algorithms, and prove invalid OIDC does not fall
through to a later endpoint. This validates metadata used for OAuth discovery;
it does not implement an OpenID relying party, fetch keys, or verify ID tokens.
References: https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderMetadata
and https://www.rfc-editor.org/rfc/rfc8414.html#section-2 .

A read-only native HTTPS fetch of Google's public OIDC discovery document passed
this validator on 2026-09-07. No sign-in, authorization code, token exchange, or
credential persistence was performed; this is discovery evidence only.

Metadata validation continuation: focused metadata/discovery/runner tests passed
83 checks. `sh scripts/check.sh` passed compilation, 905 native checks, all 1,301
pinned core schema cases, and Scribble. `git diff --check` passed. The separate
Google probe used make-oauth-http-adapters to fetch
https://accounts.google.com/.well-known/openid-configuration and validated it with
issuer https://accounts.google.com and oidc? true.

## HTTP terminal transitions and deadlines (2026-09-07)

HTTP request completion, cancellation, and timeout now arbitrate one terminal
transition. Discovery validates tools without mutating the client cache, then
publishes accepted schemas only if completion wins. Invalid header annotations
are actually excluded from listings (the previous filter retained them despite
catching validation failures). Cancelling a completed handle preserves its result.

Client construction and per-call APIs accept header and total deadlines, default
30 seconds each for ordinary requests. Subscriptions retain the header deadline
but omit the default total deadline; an explicit per-call total deadline applies.
Limits use monotonic elapsed time from request creation, accept positive finite
seconds or explicit #f, close the request custodian on timeout, and never replay
an operation. Typed timeout outcomes distinguish header and request phases.

The new HTTP lifecycle suite exercises stalled headers, stalled response streams,
subscription lifetime overrides, socket closure, stable terminal outcomes, invalid
annotation filtering, and twenty discovery/cancellation races with cache/result
consistency assertions. It passed 170 checks. Full transport conformance and the
remaining disconnect, notification-direction, and malformed-envelope matrix are
still release gates; this change does not claim them complete.

Validation: `sh scripts/check.sh` passed compilation, 1,075 native checks, all
1,301 pinned core schema cases, and Scribble. `git diff --check` passed. Evidence
is Linux/Racket 9.2 with local TCP peers; independent timeout interoperability and
other native platforms were not exercised in this continuation.

## Shared client envelope validation (2026-09-07)

Stdio and both HTTP response formats now use one private server-message checker.
It rejects malformed versions, IDs, result/error combinations, non-object results,
invalid metadata, fractional error codes, non-string error messages, unknown
result discriminators, and unexpected server requests. HTTP JSON previously
returned decoded values without the envelope checks applied to SSE; both paths
now reject unrelated response IDs. Legal errors without an ID return directly
on request-scoped HTTP; stdio fails outstanding calls because it cannot correlate
such an error. Missing resultType retains the pinned core prose's required
complete interpretation.

Task results require the request's advertised Tasks capability. Both clients
snapshot capability data at request construction, so mutation of application
hashes cannot retroactively change acceptance. Tests cover that snapshot and
malformed wire messages through real local HTTP JSON/SSE peers and stdio pipes.
The focused wire suite passed 93 checks. The official Go SDK discovery/list/call
probe passed again using protocol 2026-07-28.

This is envelope and discriminator validation, not complete method-specific
payload validation, notification-direction enforcement, or full client conformance.
Source: vendor/protocol/docs/specification/2026-07-28/basic/index.mdx and the
pinned core schema's JSONRPCResponse/Result definitions.

Validation: `sh scripts/check.sh` passed compilation, 1,168 native checks, all
1,301 pinned core schema cases, and Scribble. `git diff --check` passed. Native
verification remains Linux/Racket 9.2; the three-operation Go probe does not
establish the remaining full conformance or platform gates.

## Progress lifetime, correlation, and ordering (2026-09-07)

Runtime progress now requires the request's original string/integer token, finite
numeric progress/optional total, optional string message, and strictly increasing
values. Nested dispatch shares progress state with its enclosing operation.
Concurrent notification emission is serialized; completion closes the scope, and
background threads cannot continue emitting after the originating request ends.
Cancellation is checked before emission. Missing progress tokens cannot be used.
Malformed request progress tokens produce InvalidParams before handler execution.

Stdio validates progress for correlated active requests and freezes string tokens
used as routing keys. HTTP validates progress on its request stream, snapshots
request parameters before worker startup, and rejects duplicate active progress
tokens within one client. Terminal outcomes release HTTP tokens for reuse. Both
clients accept token zero and fractional progress; no unsupported nonnegative or
known-total constraint is imposed. Stdio continues ignoring late notifications
without an active target, including locally overflowed handles.

The progress suite passed 28 checks, including nested ordering, background
post-completion emission, invalid values, and concurrent blocked notification
output. HTTP fixtures cover unrelated/repeated progress and token reservation/
reuse. This does not establish full notification direction, rate-limiting policy,
or independent progress conformance. Source: pinned
vendor/protocol/docs/specification/2026-07-28/basic/patterns/progress.mdx.

Full validation passed compilation, 1,205 native checks and all 1,301 pinned core
schema cases. The initial Scribble build exposed a missing module-reference tag;
the manual now declares mcp/subscription so its progress API link resolves.
The final Scribble rebuild passed without warnings, and `git diff --check` passed.
Verification remains Linux/Racket 9.2; independent progress conformance was not
run in this continuation.

## Server request-envelope validation (2026-09-07)

Local dispatch, stdio, and HTTP now share request-envelope validation before
handler scheduling or transport-specific request handling. IDs are string/integer
only; invalid IDs are omitted from errors. Wrong JSON-RPC versions, non-object
messages and parameters, and response fields on incoming requests are rejected.
HTTP validates this envelope before mirrored-header checks and SSE selection.

Stdio no longer confuses JSON false with a parse-failure sentinel. It reports
InvalidRequest for false and other non-object JSON messages. Cancellation-shaped
data must pass envelope validation before reaching cancellation handling, and
malformed cancellation parameters are ignored without cancelling work or replying
to a notification. A live waiting-handler regression uses a discovery response as
a reader barrier to prove invalid cancellation has no effect.

The request-envelope suite passed 111 checks across local dispatch, stdio pipes,
and a local HTTP server. Full notification direction and cancellation-outcome
semantics remain separate gates: the existing stdio ordinary-request cancellation
acknowledgement still needs alignment with the pinned restriction that server
cancellation notifications apply only to subscriptions.

Validation: `sh scripts/check.sh` passed compilation, 1,316 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. The official Go
SDK discovery/list/call probe passed again. `git diff --check` passed. This is
Linux/Racket 9.2 verification, not full conformance or cross-platform evidence.

## Coordinated stdio cancellation outcomes (2026-09-07)

Local cancellation now resolves request handles immediately with the typed
exn:fail:request-cancelled outcome and queues its stdio notification through the
control writer. It does not wait for a server acknowledgement or writable output.
Late responses cannot overwrite cancellation; completed-handle cancellation is a
no-op. HTTP local cancellation uses the same exception type.

The server no longer sends cancellation notifications for ordinary requests.
Cancelled ordinary workers receive the existing cooperative grace period and
custodian cleanup without a protocol response. Subscriptions retain the recorded
completion-result interpretation, including forced cleanup fallback. Clients
accept a server cancellation notification only for the matching subscription;
HTTP now terminates on that legal closure instead of waiting for another result.
Conflicting request/subscription IDs and ordinary-request cancellation signals
are rejected for active requests.

Stdio retains cancelled/overflowed progress-token reservations until a late
response or connection close, avoiding misdelivery when tokens are reused. Since
ordinary cancellation may never receive a response, configurable request-limit
and progress-token-limit defaults (1,024 each) bound active handles and active/
reserved tokens. New requests fail before writing at the applicable limit. A
fresh connection clears unresolved reservations; the client never reconnects or
replays uncertain operations automatically. Request methods are snapshotted.

Tests cover immediate local outcomes, blocked cancellation output, late responses,
token reservation/reuse and bounds, both subscription closure signals, and real
server cleanup without a forbidden ordinary cancellation notification. The
focused cancellation/subscription/HTTP run passed 56 checks. Full transport race
and conformance gates remain open.

Validation: `sh scripts/check.sh` passed compilation, 1,349 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. The official Go
SDK discovery/list/call probe and `git diff --check` passed. That probe does not
exercise cancellation; independent cancellation conformance remains unverified.
Native verification remains Linux/Racket 9.2.

## Independent progress and cancellation probes (2026-09-07)

Added reproducible development fixtures for both directions: the official Go SDK
client against a Racket server, and the Racket client against the official Go SDK
server. Each waits for progress values 0, 0.5, and 1 before cancelling, verifies
that the remote handler actually stops, and performs a fresh tool listing over
the same connection. Local cancellation is checked independently from remote
cleanup. The Racket probe raises failed assertions and checks peer process exit.

The first Go-client run passed progress/cancellation/worker cleanup but failed
its final probe step because it used the old Go Ping API. The pinned changelog
removes ping in 2026-07-28; this was a probe error, not a reason to relax request
metadata validation. The corrected final operation is tools/list. The rerun passed.

`sh scripts/check-interop.sh` builds against the vendored official Go SDK and
passed all four probes: discovery/list/call, three-page pagination, Go-client
cancellation, and Racket-client cancellation. Build output and caches stay under
.cache. The SDK runtime remains Racket. The standard check script now compiles
the new Racket development fixtures; it does not require Go for native SDK tests.
These probes establish bounded stdio progress/cancellation interoperability, not
complete cancellation, HTTP, fault, or platform conformance.
The updated Scribble manual built without warnings and `git diff --check` passed.
No SDK runtime modules changed in this continuation; the full native suite was
not repeated. Evidence is from Linux/Racket 9.2 with the pinned Go development SDK.

## Nonblocking stdio requests and deadlines (2026-09-07)

Stdio request creation now enqueues serialized messages and returns a handle
without waiting for peer output. One writer handles requests and cancellation in
wire order. A configurable outbound-limit defaults to 64; a full queue rejects a
new request without writing it. Failure to queue required cancellation still
fails the connection explicitly. Existing active-request/token bounds remain.

Client construction and per-call APIs now accept a total timeout: 30 seconds by
default for ordinary requests, no default total deadline for subscriptions, and
explicit positive finite seconds or #f overrides. Monotonic deadlines include
queueing/writing/response wait, do not reset on progress, and produce the typed
exn:fail:request-timeout outcome. Synchronous convenience calls raise it.

The writer tracks queued versus started messages. Cancellation/timeout before
writing drops the request, releases its token, and does not issue a cancellation
for an unsent ID. A timeout after writing starts queues cancellation and preserves
the token reservation. Thus an expired queued mutation is never sent later; no
uncertain mutation is replayed. Late outcomes cannot replace local termination.

The new timeout suite passed 30 checks covering blocked output, queued mutation
discard, wire ordering, unsent-token reuse, bounded queues, stable timeout
outcomes, and subscription overrides. The existing cancellation/lifecycle/overflow/
subscription suites passed 76 focused checks before the full validation run.

Validation: `sh scripts/check.sh` passed compilation, 1,379 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. All four probes in
`sh scripts/check-interop.sh` passed with the asynchronous writer. `git diff
--check` passed. Evidence remains Linux/Racket 9.2 plus the pinned Go SDK; full
transport conformance and native platform gates remain open.

## Complete multi-content resource embedding (2026-09-07)

Resource bodies can now return resource-contents with an explicit sequence of
text/binary/JSON presentations. Reads preserve every part. Immediate and durable
embedding no longer take only the first content item: tool content expands in
source order, and prompt content lowers to individual messages preserving roles.
Mounted URI mappings apply to every embedded item. Empty sequences add no content.

Text presentations concatenate embedded text parts without implicit separators;
binary parts require explicit conversion. JSON presentations and structured tool
values represent a multi-content embedding as an array. Single-item embeddings
retain their prior object representation. Durable child results store all parts,
and retries retain the completed content without reconstructing parent handlers.
Rendering storage uses render/2 and rejects old records with a version diagnostic
because render/1 may already have discarded content; no silent migration is made.

The new multi-content suite plus existing embedding/presentation suites passed
55 checks, including mixed binary/text, empty content, mounted views, SQLite
close/reopen, stable terminal retries, and old-record rejection. Added the runnable
examples/multi-content.rkt and an independent Go SDK probe. All five probes in
scripts/check-interop.sh passed, including multi-content resource reads, tool
embeddings, and prompt message lowering. Full durable embedding crash/ownership/
concurrency coverage remains a separate release gate.

Validation: `sh scripts/check.sh` passed compilation, 1,408 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. All five independent
Go probes passed; `git diff --check` passed. Native verification remains Linux/
Racket 9.2. The private JSON marker representation also needs a separate collision
audit against arbitrary application JSON; these tests do not establish that gate.

## Rendering provenance and stable workflow rendering (2026-09-07)

The collision audit reproduced that ordinary JSON could impersonate deferred
embedding and multi-content markers. SDK-created markers now carry a private
Racket impersonator property. They remain JSON-shaped hashes for schema/codecs,
but matching keys or an ordinary JSON round trip cannot acquire the property.
Only marked values activate embedded reads or content-group expansion.

SQLite stores provenance paths in separate state_marks, argument_marks, and
journal event_marks columns. These paths are generated by the SDK, not read from
application JSON. Restoration reconstructs private properties only at recorded
paths. Schema upgrades add nullable sidecars under a transaction; ordinary legacy
rows remain readable, while ambiguous legacy marker-shaped data fails with an
explicit recovery diagnostic. Rendering records now use render/3. There is no
global transformer registration or compile-time application evaluation involved.

The new test also exposed duplicate child reads when retrying a completed
workflow: rendering used a fresh instance each time. A stable rendering key bound
to the stored workflow handle now retains child outcomes across those retries.
The collision/embedding focused run passed 66 checks. A three-process restart
fixture passed, proving a genuine marker survives storage, an identical JSON
copy stays data, and a terminal retry does not repeat the child read. An actual
pre-sidecar SQLite schema migration is covered, including ambiguous-row rejection.

Validation: `sh scripts/check.sh` passed compilation, 1,435 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. All five probes in
`sh scripts/check-interop.sh` and `git diff --check` passed. Evidence remains
Linux/Racket 9.2; full release conformance and platform gates remain open.

## Storage-open failure cleanup (2026-09-07)

Opening a store now owns its SQLite connection until successful construction and
disconnects it on setup failure. Cleanup preserves the original raised value.
Worker-directory setup additionally verifies that the path is a directory:
make-directory* accepted an existing file, previously allowing a broken store to
appear successfully opened. The conflicting file is preserved.

New tests inspect custodian registrations immediately after failure, without GC,
for a worker-path conflict, a failed schema migration, and an arbitrary value
raised by a security guard. They also verify migration rollback and reopening
after the obstruction is removed. The focused storage/provenance/worker-lock run
passed 36 checks. This is concrete connection ownership evidence, not a claim
that the entire storage recovery matrix is complete.

Validation: `sh scripts/check.sh` passed compilation, 1,445 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. `git diff --check`
passed. Independent transport probes were not repeated for this storage-only
change. Native verification remains Linux/Racket 9.2; release completion remains
unproven against the outstanding implementation and conformance gates.

## Upstream resources, prompts, and completion (2026-09-07)

Pinned upstream interfaces now generate ordinary resource, resource-template, and
prompt descriptors in addition to tools. Descriptor construction copies snapshot
JSON without contacting the peer. Before first invocation, conservative checks
compare supported versions and capabilities as well as published declarations.
Changed interfaces fail before application invocation. This is one initial check,
not continuous compatibility monitoring or schema subsumption analysis.

Resource reads preserve all returned content, including explicit per-content URIs,
MIME types, and binary data. The new resource-content presentation wraps such an
explicit object. Known resource links and embedded-resource URIs resolve through
mounted declaration identity; arbitrary structured JSON and unknown external URIs
stay data. Removed known references and ambiguous upstream URI matches fail.
Complex templates require explicit argument descriptors and inverse matchers.

Prompts retain complete result descriptions and omit absent optional arguments.
Completion descriptors forward original peer references and context while local
views retain transformed names and URIs. Completion handlers may return a complete
completion object to preserve total/hasMore, or the existing string list. Upstream
responses with an absent resultType normalize to complete under the client's
pinned-schema fallback rule. MRTR and Tasks still fail explicitly pending durable
handle translation; this continuation does not establish that integration gate.

Validation: `sh scripts/check.sh` passed compilation, 1,475 native checks, all
1,301 pinned core schema cases, and Scribble without warnings. Explicit recompilation
and `raco test tests/upstream.rkt` passed 34 checks after the final ambiguity change.
All five existing probes in `sh scripts/check-interop.sh` passed, and `git diff
--check` passed. The new upstream forwarding behavior has native peer-fixture
coverage; those five Go probes exercise the shared runtime but are not an
independent end-to-end upstream bridge test. Native evidence remains Linux/Racket
9.2. Full release implementation, conformance, and platform gates remain open.

## Additive scope requirements in interface views (2026-09-07)

view now accepts #:require-scopes. The data API accepts make-interface
#:requirements, an identity-keyed mapping from included declarations to scope
lists; interface-requirements exposes the immutable copied mapping. Invalid scope
tokens and requirements for absent declarations fail construction. Nested views
accumulate requirements, and renaming, URI mappings, mount-interfaces, and language
module collection preserve them. Tool annotations are not authority declarations.

Runtime scope policy combines descriptor requirements with the application's
required-scopes callback. Checks precede handler execution and cache reads, inherit
completion target requirements, and run again for embedded resources, MRTR retries,
and task access. Task handles whose executable is absent from an interface are
rejected. HTTP insufficient-scope challenges use the combined requirements. Task
notification publication rechecks subscriber authorization and principal expiry.
Completion reference discriminators are now checked during dispatch as well as
scope resolution, preventing forged reference types from bypassing target policy.

Discovery/listing remains visible unless application runtime policy restricts it;
these requirements do not automatically redact declarations. Scoped operations
require verified principals, including on local/stdio dispatch. This is enforcement
within a configured runtime, not a sandbox against trusted Racket authors building
another interface. Adapter replacement and enforced effect restrictions remain open.

Validation: sh scripts/check.sh passed compilation, 1,501 native checks, all 1,301
pinned core schema cases, and Scribble without warnings. The subsequently added
view-task-notifications.rkt passed eight additional checks after explicit raco make:
a revoked subscriber receives no updates while another authorized subscriber for
the same principal receives working/completed notifications. The initial focused
scope/task/HTTP run passed 74 checks; the HTTP fixture now exercises view-derived
scope challenges. Early test fixture syntax/language-path errors and dependent
compiled-module mismatches were corrected before these passing runs.
All five existing Go probes in sh scripts/check-interop.sh passed, and git diff
--check passed. These probes verify shared-runtime interoperability, not an
independent authorization conformance suite. Native verification remains Linux/
Racket 9.2; the complete implementation and release gates remain open.

## Per-declaration adapter replacement and durable versions (2026-09-07)

view now accepts #:adapters with symbol-keyed versioned-effect-adapter values.
The data API's #:adapter-bindings maps included declarations to copied adapter
maps; interface-adapter-bindings exposes them. Explicit versions are required for
view replacements. Existing unversioned effect-adapter runtime bindings remain
supported. The effect descriptor definitions now live in mcp/effect.rkt and are
re-exported through mcp/workflow and mcp.

Bindings survive nested views, selection, mounting, and language module collection.
They override runtime defaults for their own declaration, including tool, resource,
prompt, and task workflows. Sibling mounts can bind the same effect symbol to
different adapters without mutating the shared original descriptor or runtime map.

Referenced versioned adapter identities/policies contribute to saved workflow
fingerprints and durable parent rendering fingerprints. An incompatible adapter
version fails before advancing an existing execution. Task workflow records use
the same fingerprint when created, so task continuation cannot silently substitute
an adapter. The version is an application compatibility promise, not automatic
procedure equivalence or imported-helper hashing. Arbitrary Racket I/O is not
intercepted; enforced effect restrictions remain a separate gate.

New tasks retain their published tool operation name, allowing sibling mounts of
one workflow to recover and update using their own adapter bindings. Legacy task
records without that identity reject ambiguous candidate executables instead of
selecting one by list order. Unambiguous legacy resolution remains supported.

Validation: sh scripts/check.sh passed compilation, 1,523 native checks, all 1,301
pinned core schema cases, and Scribble without warnings. Explicit recompilation
and raco test tests/view-adapters.rkt passed 14 checks after the final legacy-task
ambiguity change. Coverage includes independent sibling bindings, resource/prompt
workflows, SQLite close/reopen, unchanged-version retries, changed-version rejection
before effects, and legal failed-task outcomes without invoking replacement code.
All five existing Go probes in sh scripts/check-interop.sh and git diff --check
passed. These probes cover the shared SDK runtime, not an independent adapter or
upstream durable bridge conformance suite. Native evidence remains Linux/Racket 9.2;
full executable fingerprint, effect restrictions, and release gates remain open.

## Fresh independent conformance and optional MRTR state (2026-09-07)

Re-ran the pinned harness against the current server: the final 40-scenario all
suite records 142 SUCCESS, 4 FAILURE, 1 WARNING, 2 SKIPPED, and 1 INFO checks under
test-artifacts/conformance-server-final-20260907-0855. The headline harness summary
omits warnings from its failure total; raw checks.json and summary.json preserve
all statuses. This is not an unqualified passing release gate.

The four failures are the previously documented sampling, roots, mixed-input,
and sampling-capability fixtures excluded by the approved release scope. The
remaining warning is input-required-result-ignore-extra-params: that fixture sends
recognized and unrecognized inputResponses without making an initial request or
echoing a continuation. This durable workflow requires its opaque state; accepting
that unsolicited response would bypass its execution binding. Native continuation-
rounds tests prove unknown keys are ignored when a valid state is supplied. No
upstream harness checks were rewritten or relaxed.

A second warning exposed missing data.uri on resource-not-found errors. The runtime
now includes it. The independent resource error scenario passes all four checks
in conformance-resource-error-fixed-20260907-0855 and in the final full server run.
The two server skips concern list-changed notification fixtures; the informational
SSE check records that the server used JSON responses. Those do not prove live
subscription or SSE conformance.

Eight non-authorization client scenarios now pass 62 checks, with four expected
skips for deprecated roots/sampling capability checks and removed initialization.
Results are in conformance-clients-fixed-20260907-0851: tools_call 2, request-metadata
6, http-standard-headers 9, http-custom-headers 18, http-invalid-tool-headers 12,
json-schema-ref-no-deref 1, sep-2322-client-request-state 5, and the added-after-release
json-schema-2020-12-preservation probe 9. The last probe is useful evidence, not a
frozen release-scoring requirement. Authorization scenarios and Tasks extension
scenarios remain unrun against complete fixtures.

The initial client run exposed a fixture that ignored MCP_CONFORMANCE_CONTEXT
header-edge values and never invoked the explicit interaction runner. The fixture
now uses supplied tool arguments, an explicit decline/cancel callback policy, and
the schema-echo scenario's required data round trip. SDK code has no scenario-name
branches. Initial failing artifacts remain preserved.

The runner itself incorrectly required requestState and resultType. It now handles
optional state/inputRequests, clears previous-round fields when absent, echoes
opaque state unchanged, defaults missing resultType to complete, and rejects malformed
input-required results before automatic retry. Round limits must be positive
integers. Native tests preserve decline/cancel outcomes and verify exceptions do
not replay uncertain requests. The official client MRTR scenario passes all five
checks again after the final malformed-result guard.

Validation: sh scripts/check.sh passed compilation, 1,547 native checks, all 1,301
pinned schema cases, and Scribble. After the final resource URI diagnostic change,
explicit compilation and request-envelope/interaction suites passed 136 checks.
The development harness's 614 source/package files matched the vendored copy
byte-for-byte. git diff --check passed. Native evidence remains Linux/Racket 9.2.

## Tasks conformance fixtures and checkpoint lock ownership (2026-09-07)

Added dev/conformance-tasks.rkt with synchronous, optional-task, required-task,
error, cancellation, and single/batched elicitation fixtures. workflow supports
explicit #:execution task-optional: it queues a task only when the client declares
the Tasks extension, otherwise runs the ordinary MRTR workflow. Existing task mode
still requires the capability before queueing. Constructors reject unknown modes
and task modes without a workflow; language errors point at an invalid mode.

The first actual Tasks harness run exposed a lock defect: checkpoint computation
held SQLite's transaction and blocked polling/cancellation while sleeping. Checkpoint
computation now retains its exclusive instance worker claim but releases SQLite.
The result and stage advance commit under a new transaction after rechecking
cancellation. A deterministic semaphore-blocked regression proves polling and
cancellation finish while the checkpoint is still blocked; releasing it cannot
commit the checkpoint or run completion after cancellation. Transactional effects
retain their explicit transaction policy. This does not prove all host callback
or codec execution paths are free of database-lock contention.

The rerun exposed additional defects now fixed: task capability errors carry
requiredCapabilities data; unknown task IDs return -32602; tasks/update ignores
unrecognized response keys and avoids restarting on an all-unknown update.
Recognized elicitation responses validate before state transitions, so malformed
input leaves the task input_required. Elicitation validation is shared through a
private helper. The batched elicitation fixture was also corrected to accept the
harness's authored name/confirm payload, rather than rejecting its extra name.

Nine Tasks scenarios were explicitly selected with --force because extension
scenarios are outside the core dated timeline selector. The initial no-force run
was entirely skipped and is not passing evidence. Final raw artifacts under
conformance-tasks-final-20260907-0905 record 41 SUCCESS, 1 FAILURE, and 1 SKIPPED.
Lifecycle, capability negotiation, wire fields, request-state removal, MRTR input,
dispatch/envelopes, and required-task error scenarios pass. The initial lock-failure
run was intentionally interrupted after establishing cross-scenario interference;
its partial/failing artifacts remain preserved.

The remaining failure expects Mcp-Name to mirror tasks/get taskId. The pinned core
transport table defines Mcp-Name for tools/call, resources/read, and prompts/get,
using params.name/params.uri; the vendored Tasks schema specifies taskId but does
not define that header mapping. This is an unresolved harness/specification
boundary, not a waived release gate. No undocumented required header was added
solely to pass that assertion. The notification scenario explicitly skips itself
pending an upstream subscriptions/listen rewrite. MRTR-before-task-creation
composition still lacks a complete fixture/runtime path and was not run here.

Validation: sh scripts/check.sh passed compilation, 1,567 native checks, all 1,301
pinned core schema cases, and Scribble without warnings. The focused checkpoint,
optional-task, restart, and task checks passed after correcting an invalid test
fixture stage; updated input-validation tests also passed. All five Go probes in
sh scripts/check-interop.sh passed. git diff --check passed after removing an extra
blank line left by helper extraction. Native evidence remains Linux/Racket 9.2;
Tasks composition, the header discrepancy, and full release gates remain open.

## Distribution dependency refresh (2026-09-07)

A clean source-distribution setup exposed two development probes importing
RackUnit as a runtime dependency. RackUnit is deliberately a build dependency;
the native SDK does not require it. A package-root compile omission did not apply
to the dev collection in this multi-collection package. Added dev/info.rkt with
compile-omit-paths set to all. Development sources remain in the archive and
verification scripts explicitly compile/run the probes.

Rebuilt with python3 scripts/package.py, then ran env -u PLTCOLLECTS raco setup
--check-pkg-deps --pkgs racket-mcp inside the isolated Racket environment. The
fresh setup completed successfully, including documentation and dependency checks,
on Linux/Racket 9.2. The preceding failed checks exposed the packaging defect and
are not counted as passes. No SDK behavior changed in this packaging correction;
the preceding 1,567 native checks and five Go probe results are recorded above.

After the packaging correction, sh scripts/check-interop.sh passed all five probes
again, including explicit compilation of the development cancellation client.
Two consecutive source archive builds from identical inputs produced the same
SHA-256. This establishes repeatability in this environment, not cross-platform
archive or complete release verification.

## Completion reference checking (2026-09-07)

Completion declarations now enter the source-aware declaration IR. Expansion
resolves locally declared targets by lexical identifier, rejects non-resource/
non-prompt targets, unknown arguments, and duplicate routes, and emits source-
attached completion entries in the manifest. Imported or host-supplied targets
remain explicitly dynamic; their expressions and handlers are not evaluated by
the compiler. Manifest diffs distinguish each target/argument route so removing
one completion cannot be hidden by another completion on the same target.

make-interface now checks completion target membership, argument existence, and
route uniqueness. Completion descriptors check symbol arguments and binary handler
arity. make-runtime applies the same interface checks to raw public descriptors
before task recovery can run. Views retain their existing target remapping and
remove completions belonging to excluded targets. Under ordinary require mcp,
completion now constructs and returns its descriptor, evaluating the handler
expression once; previously registration outside the language discarded that
expression entirely.

The focused regression covers dynamic constructors, imported/renamed mounted and
absent targets, lexical shadowing, expansion-time errors, manifest inspection
without parent instantiation, route diffs, and descriptor evaluation count. Initial
regressions exposed registration nested too late inside a generated let; moving
metadata registration to the declaration level fixed it. The first full suite
also exposed two old manifest assertions that omitted the collection extension's
completion; those expectations now include the new declaration entry.

sh scripts/check.sh passed compilation, 1,595 native checks, all 1,301 pinned core
schema cases, and Scribble. All five Go probes in sh scripts/check-interop.sh
passed. A final compiler refinement excludes server metadata expressions from
binding candidates; explicit recompilation and the compiler, completion-reference,
declaration-manifest, and extension suites then passed 65 focused checks.
This is completion-reference coverage, not complete cross-module analysis of
references hidden in arbitrary Racket handlers. The broader compiler and release
gates remain open. Native evidence remains Linux/Racket 9.2.

## Declaration schema and argument contracts (2026-09-07)

Literal schema checks now cover tool argument/output schemas, resource and prompt
arguments, shape fields, and workflow checkpoint/input/grouped-input/effect
representations, rather than only named schema declarations. The shared expansion
helper inspects reader constants and lexically bound Racket quote forms; it never
evaluates computed schema expressions. Malformed literals produce syntax errors
attached to the actual schema source. Boolean schemas remain valid, and a host
macro named quote retains its own expansion semantics.

Tool, resource, and prompt constructors now share argument validation: descriptor
lists, unique symbolic names, boolean optional flags, valid schemas, and unary
optional defaults. make-resource previously omitted duplicate/schema checks.
Resources now also reject empty wire names. make-interface validates arguments and
tool input/output schemas in raw public descriptors, so make-runtime's interface
validation rejects malformed schemas before recovery starts. These checks do not
invoke defaults or handlers. Computed resource schemas still evaluate once in
order, and defaults evaluate only when binding absent arguments.

The new declaration-schemas suite contributes 49 checks, covering each source
schema position, source locations, raw and dynamic constructors, evaluation
order/count, boolean schemas, custom format annotations, and lexical quote
shadowing. Initial test-fixture reader errors were corrected before validation.
sh scripts/check.sh passed compilation, 1,644 native checks, all 1,301 pinned core
schema cases, and Scribble without warnings. All five Go probes in
sh scripts/check-interop.sh passed, as did git diff --check. Native evidence remains
Linux/Racket 9.2. This improves constructor/schema equivalence; complete descriptor
contract parity and the remaining compiler/integration/release gates remain open.

## Checked RFC 6570 URI templates (2026-09-07)

Replaced permissive expression splitting with a shared native parser supporting
RFC 6570 variable names, operators, and modifiers. Invalid literals, malformed
expressions, unsupported reserved operators, and invalid prefix modifiers fail
explicitly. Expansion handles Unicode literal encoding, percent-triplet preservation
for reserved/fragment expansion, percent-encoded variable names, undefined composite
members, empty values, and Unicode prefix boundaries. Composite values reject prefix
modifiers. The parser incorporates verified RFC erratum 6937 admitting apostrophes
in literal text; the initial two corpus failures exposed that erratum.

Generated inverse matchers now accept only unreserved characters and valid percent
triplets in simple captures, require strict UTF-8 decoding, and reject ambiguous
or complex templates without an explicit matcher. Resource construction checks
syntax and declared variables even when a matcher is supplied. Literal declaration
errors retain URI source locations. Views preserve variable sets across URI
remappings. Upstream adapters use the same variable parser rather than their old
ASCII-name regex; a full-suite failure exposed that remaining extractor and it was
corrected before the final run. Dotted/digit-leading upstream variables have a
separate regression.

Pinned uri-templates/uritemplate-test at
4171dac22aa67fc710b3f6df308a50bd08552986 under vendor/uri-template-tests, retaining
LICENSE and README. Its six file hashes are included in vendor/LOCK.json, and the
explicit fetch-inputs.py command supports this input. All 864 vendored file hashes
were verified. The unmodified independent corpus passes all 270 cases; native URI
regressions add 41 checks. No runtime/compile-time network fetching was introduced.
General overlap analysis between separate resource templates remains incomplete;
generated matchers return strings, and composite/domain inverses require adapters.

References: https://www.rfc-editor.org/rfc/rfc6570 and the verified EID 6937
correction recorded at https://www.ietf.org/rfc/inline-errata/rfc6570.html .

Final validation: sh scripts/check.sh passed compilation, 1,957 native checks
(including the 270 independent URI corpus cases), all 1,301 pinned JSON Schema
core cases, and Scribble without warnings. All five Go probes passed against the
new URI engine; after the upstream extractor correction, the focused upstream/URI
suites passed 345 checks before the final dotted-variable regressions/full run.
git diff --check passed. Native verification remains Linux/Racket 9.2; this is
URI behavior coverage, not completion of the full SDK release gates.

Staged-check qualification: the pre-staging tracked diff was clean, but the full
staged diff reported upstream trailing whitespace and an extra terminal blank
line in the newly vendored URI fixtures. Those bytes are retained to preserve the
verified upstream hashes. git diff HEAD^ HEAD --check -- . ':!vendor' passed for
the SDK/test/tooling changes. The full staged whitespace check was not a pass;
no upstream fixture was rewritten to silence it.

## Generated resource-route overlap analysis (2026-09-07)

Generated URI matchers now retain a private regular-language representation.
uri-matchers-overlap computes their intersection using finite-state search over
URI tokens and percent-encoded UTF-8 validity. It returns a concrete accepted URI
for overlap, false for disjointness, or unknown for arbitrary custom procedures.
It never invokes custom matchers. The search has a 10,000-state default limit,
configurable through #:max-states; exhaustion raises rather than claiming safety.

make-interface rejects overlapping generated routes, including fixed/template
collisions and overlaps introduced by mounts or views. make-runtime inherits this
check before recovery. The source-aware declaration pass performs the same check
for locally known literal resources with generated matchers and attaches errors
to the conflicting URI source. Computed/custom matchers remain subject to runtime
ambiguity checks; arbitrary Racket procedures cannot be analyzed as regular
languages from their mere presence.

The new overlap suite checks witnesses against both procedural matchers, disjoint
UTF-8 cases, Unicode boundaries, empty captures, construction/mount/view rejection,
source errors, custom matcher non-execution, budget exhaustion, and bounded
independent enumeration of small route languages. An initial expected-overlap
fixture actually contained an incomplete literal UTF-8 sequence; its disjointness
expectation was corrected. Reader errors in integration fixtures were corrected
before passing tests. The new check also diagnosed an unintended collision in the
upstream dotted-name fixture, now placed under a distinct prefix. The intentional
upstream collision test now expects rejection during construction.

The focused overlap/upstream run passed 231 checks. This closes overlap checking
for generated simple matchers, not inference of arbitrary custom matcher behavior
or the broader remaining compiler, durable interaction, and release gates.

Final validation: sh scripts/check.sh passed compilation, 2,152 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble without warnings. All five
Go probes in sh scripts/check-interop.sh passed. git diff --check passed. A direct
probe also confirmed generated fixed matchers reject a trailing raw newline.
Verification remains Linux/Racket 9.2; the full SDK objective remains incomplete.

## Explicit replacement after task recovery (2026-09-07)

Tasks failing with an outstanding uncertain manual effect now record private
recovery metadata alongside the legal failed-task error. This includes an adapter
exception on the first attempt with a persisted intent, not only an uncertainty
exception encountered on a later run. The metadata binds eligibility to a workflow
revision, effect stage, and subsequent journaled repair.

retry-runtime-task! is an explicit local API accepting the failed task ID,
principal, and current capabilities. After recover-workflow! records an outcome
or authorizes effect retry, it creates a new task backed by the existing workflow.
It checks ownership, expiry, executable/adapter compatibility, required capabilities,
and runtime task/operation authorization before allocation; the worker reauthorizes.
Capabilities are copied for this interaction and persisted for startup recovery.
The lower-level retry-recovered-task! accepts explicit workflow/store/owner and
adapter, custodian, and authorization integration. No new protocol method or
automatic replay of an uncertain mutation was introduced.

Replacement creation and bidirectional journal links share one transaction.
Repeated/concurrent calls return the recorded replacement ID, even while its effect
is blocked. The original failed task's result and revision remain unchanged.
Checkpoints and effect keys are retained, and replacement expiry never exceeds the
original task/workflow expiry. Abandoned and unrepaired executions are rejected.
Only failures with the explicit recovery metadata are eligible; historical messages
are not interpreted to guess eligibility.

The task-recovery suite passed 32 checks: observed outcomes avoid another effect,
retry repairs reuse the same key, foreign/capability/authorization failures allocate
nothing, incompatible code is rejected, SQLite reopen preserves replacement mapping,
eight concurrent callers get one handle/journal entry, and terminal task revisions
remain unchanged. Test/read-syntax defects were corrected before the passing run.
This is not a complete process-crash or every-boundary recovery matrix; those and
the broader remaining SDK release gates remain open.

Final validation: sh scripts/check.sh passed compilation, 2,184 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. The first full run exposed
a changed diagnostic for incompatible saved code; its existing recovery message
was restored while replacement eligibility remains restricted to uncertain-effect
metadata. The final run passed that regression. All five Go probes passed; git
diff --check passed. Scribble was rebuilt after clarifying the low-level callback's
raise-on-denial contract. Evidence remains Linux/Racket 9.2, not full independent
Tasks conformance or every-boundary process-crash verification.

## Task replacement across process termination (2026-09-07)

Added task-recovery-process.rkt and its separate executable worker. The parent
kills a live child after four signalled boundaries: repair before replacement
allocation, committed replacement before its worker starts, an external manual
effect before recording its result, and terminal replacement completion. Each
case reopens the SQLite store in a fresh process through the public runtime APIs.
The worker uses authorization and adapter callbacks to stop at these boundaries;
no production-only fault hooks were added.

The focused suite passed 60 checks. Restart preserves replacement identity and
terminal outcomes; repeating replacement retrieves the recorded handle. Killing
an in-flight manual effect leaves it uncertain, and startup recovery fails that
task without another adapter invocation. Recording an observed outcome then
creates a third task. Both earlier failed tasks retain their result and revision.
The effect log verifies that explicitly authorized retry uses the original key,
while outcome repair does not execute the effect again. Reports are sorted by
handle so assertions do not depend on SQLite row order.

These cases extend actual process-crash coverage for task replacement. They do
not establish every workflow, input, nested rendering, transaction, expiry, or
concurrent recovery boundary. The overall release remains incomplete.

Final validation: sh scripts/check.sh passed compilation, 2,244 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. git diff --check passed.
No runtime implementation changed in this batch; the five Go probes were not
rerun, and their preceding results remain historical evidence. Native verification
is Linux/Racket 9.2; other platforms and the full release gates remain open.

## Workflow control callbacks without SQLite lock ownership (2026-09-07)

Branch selectors, branch joins, completion handlers, and completion change-key
callbacks previously ran inside the stage transaction. A blocked callback could
therefore prevent task polling or cancellation from acquiring storage. They now
run under the existing exclusive instance worker claim but outside SQLite's
transaction, then commit their stage transition and journal/outbox together.
Cancellation is rechecked before committing. Checkpoint environment decoding also
moves outside the transaction; this does not move checkpoint encoding, input
construction, or effect/recovery codec callbacks out of their existing boundaries.
Transactional effects retain their shared application/storage transaction.

The new control-stage-lock suite passes 84 checks across branch, join, completion,
and change-key callbacks, both with and without cancellation. Semaphores hold each
callback while separate requests poll and cancel. The tests check transaction
absence, responsive requests, one callback execution, completed normal results,
and no cancelled transition, persistent value, result, or change outbox. Existing
branch/control-flow/checkpoint/freshness suites passed 49 checks. Replay-safe host
callbacks may run again after a crash before commit; this change does not promise
exactly-once arbitrary application computation.

Final validation: sh scripts/check.sh passed compilation, 2,328 native checks,
all 1,301 pinned core schema cases, and Scribble. All five Go interoperability
probes passed with sh scripts/check-interop.sh. git diff --check passed.
Evidence remains Linux/Racket 9.2; remaining input/effect/codec callback ownership
and the complete SDK release gates remain open.

## Input construction without SQLite lock ownership (2026-09-07)

Single and grouped elicitation constructors now execute outside the transaction
under the workflow's exclusive instance claim. The runtime validates group
identities and saves pending request data with a revision-checked transition
before processing responses or publishing input_required. Cancellation is checked
before this save. Retries read saved request data, including after an interruption
between saving the request and returning it, instead of re-entering application
construction. A crash before the save can still rerun replay-safe construction.

The new input-stage-lock suite passed 48 checks covering single/group requests,
normal execution, and cancellation. Blocking constructor callbacks expose no
current storage transaction; concurrent task polling and cancellation complete.
Cancelled construction leaves no pending request. Successful requests are saved,
reused by a continuation, and completed through task updates without repeating the
constructor. Existing input-group, continuation-round, and task suites passed 36
checks, including partial responses and SQLite reopen. This does not establish
every process-crash boundary or move effect and recovery codecs out of transactions.

Final validation: sh scripts/check.sh passed compilation, 2,376 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. All five probes passed with
sh scripts/check-interop.sh. git diff --check passed. Verification remains
Linux/Racket 9.2; remaining codec/effect lock boundaries, the full crash matrix,
and the overall release gates remain open.

## Checkpoint and external-effect encoding lock boundaries (2026-09-07)

Stage representation preparation is now separate from the atomic advancement.
Checkpoint encoders and nontransactional effect-result encoders execute outside
SQLite while the instance worker claim remains held. The prepared value, stage
journal, and committed changes still persist together. Checkpoint cancellation is
checked before advancement. An already acknowledged external effect still records
its outcome and outbox after cancellation; it does not overwrite the cancelled
task result or execute workflow completion. Transactional effect encoding remains
inside the mutation transaction so invalid representations roll back the mutation.

The codec-stage-lock suite passed 88 checks for blocked checkpoint/manual/idempotent
encoders, responsive polling and cancellation, single encoding/effect invocation,
checkpoint non-advancement after cancellation, and retained external outcomes and
change records. Transactional success/failure checks prove connection ownership
and mutation/outbox/stage rollback on encoding errors. Existing codec, checkpoint,
freshness, and recovery-race suites passed 61 checks. Effect input/environment and
explicit recovery codecs still require their separate lock-boundary work; this
change does not claim every application callback or crash boundary is covered.

Final validation: sh scripts/check.sh passed compilation, 2,464 native checks,
all 1,301 pinned core schema cases, and Scribble. All five Go probes passed with
sh scripts/check-interop.sh. git diff --check passed. Verification remains
Linux/Racket 9.2, with effect-input/recovery callback boundaries and the broader
SDK release gates still open.

## Recovery encoding without SQLite lock ownership (2026-09-07)

Observed-outcome recovery now reads and checks the owned pending effect under its
exclusive worker claim, encodes outside SQLite, and commits the repaired state,
recovery journal, and change outbox together with the existing revision CAS.
Calls inside an existing transaction on the same store are rejected so application
nesting cannot silently retain SQLite during encoding. Retry and abandon retain
the same ownership/stage checks and atomic journal/state updates.

The recovery-codec-lock suite passed 50 checks. A blocked encoder exposes no
current connection; concurrent reads finish, competing repairs fail promptly,
and foreign/nested-transaction requests do not invoke the encoder. Encoding
failure preserves state, journal, and outbox. A deliberately changed storage
revision rejects stale repair and rolls back its journal/outbox, then releases the
claim for a later repair. Existing codec, recovery-race, and task-recovery suites
passed 59 checks. Effect-input callbacks and the broader crash/concurrency and
release gates remain separate work.

Final validation: sh scripts/check.sh passed compilation, 2,514 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. All five Go probes passed
with sh scripts/check-interop.sh. git diff --check passed. Native evidence remains
Linux/Racket 9.2; effect-input preparation and full SDK release gates remain open.

## Effect-input preparation without SQLite lock ownership (2026-09-07)

Effect input computation and environment decoding now execute outside SQLite
under the instance worker claim for transactional, manual, and idempotent policies.
Cancellation is checked before transactional adapter invocation or external intent
creation. Transactional mutation and encoding remain in one transaction; external
intent/journal persist before invocation, and acknowledged outcomes retain their
existing atomic result/outbox behavior. Uncertain manual intents reject retries
before input preparation or environment decoding runs again.

The effect-input-lock suite passed 80 checks across all three policies, with and
without cancellation. Blocked preparation allows polling and cancellation; cancelled
preparation produces no adapter call, intent, value, completion, or change outbox.
Normal execution retains the appropriate adapter connection. A manual-uncertainty
regression verifies retry does not re-evaluate input or change stored state.
Existing workflow, recovery-race, codec-lock, and freshness suites passed 144 checks.
This completes the identified stage-callback transaction separations, not every
crash/cancellation schedule or the broader SDK release requirements.

Final validation: sh scripts/check.sh passed compilation, 2,594 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. All five Go probes passed
with sh scripts/check-interop.sh. git diff --check passed. Verification remains
Linux/Racket 9.2; broader compiler, integration, conformance, crash-matrix, and
platform requirements remain open.

## Imported resource completion metadata (2026-09-07)

Private resource transformer bindings now carry the original declaration name and
argument names alongside their existing lexical target and arity. Completion
expansion checks imported/re-exported resource arguments under both #lang mcp and
ordinary require mcp. The module finalizer recognizes aliases of an imported
resource when rejecting duplicate routes and emits a known resource target using
its original name. No global registration table or handler/metadata evaluation is
used to discover these values. Runtime interface membership checks still apply.

The new imported-resource-metadata fixtures cover ordinary and workflow resources,
import and re-export renaming, misspelled arguments, duplicate aliases, reference
arity, forward declarations, and host shadowing. A throwing provider and handler
prove manifest inspection and expansion do not instantiate either. Together with
existing completion/compiler/domain suites, the focused run passed 61 checks.
The first run required recompilation after the private struct changed. A later
forward-reference test exposed namespace lookup of quoted host syntax; unavailable
static bindings now defer to the finalizer's local declaration checks rather than
failing immediate resource lookup. Final focused tests passed after that fix.

This closes imported resource completion metadata, not imported prompt metadata,
references hidden in arbitrary host handlers, complete cross-module interface
analysis, or the remaining public extension API and release gates.

Final validation: sh scripts/check.sh passed compilation, 2,608 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. All five Go probes passed
with sh scripts/check-interop.sh. git diff --check passed. Native evidence remains
Linux/Racket 9.2; the broader compiler and full SDK release gates remain open.

## Imported prompt completion metadata (2026-09-07)

Prompt declarations now export a lexical transformer wrapper carrying their
original name and argument names. Ordinary host references resolve to the hidden
syntax-spec operation value, and operation-reference explicitly unwraps prompts
before invoking its checked core. Completion checks and manifests share the
imported-target path for prompts and resources. Imported prompt arguments and
duplicate aliases are checked without evaluating providers or handlers; manifests
record the original prompt name and kind instead of marking the target unknown.

The focused imported-prompt/domain-binding/completion run passed 66 checks. New
fixtures cover plain and workflow prompts, renaming and re-export, duplicate
aliases, misspelled arguments under both languages, forward declarations, host
shadowing, throwing-provider manifests, operation references, dynamic-require,
immutable binding errors, schema-kind rejection, and phase-shifted value use.

A rename-transformer probe first lost metadata during export. Preserving that
transformer via not-free-identifier=? instead broke syntax-spec compiled-name
lookup. The final explicit wrapper avoids those aliasing semantics and passes the
binding checks; neither failed probe is counted as passing evidence. The Racket
reference documents the export/alias behavior at
https://docs.racket-lang.org/reference/stxtrans.html.
Whole-interface references, the complete extension API, and broader release gates
remain open; these checks concern declared completion targets.

Final validation: sh scripts/check.sh passed compilation, 2,627 native checks,
all 1,301 pinned JSON Schema core cases, and Scribble. All five Go probes passed
with sh scripts/check-interop.sh. git diff --check passed. Native verification
remains Linux/Racket 9.2; complete interface-reference and release gates remain open.

## Public extension binding queries (2026-09-07)

Added mcp/extension with public immutable mcp-binding-info data, lookup-mcp-binding,
and require-mcp-binding. Extension authors import it for-syntax; the implementation
uses lexical resource/prompt metadata and syntax-spec binding predicates, without
exporting private classes/IR or compiling/evaluating application references.
Value and effect spaces are explicit. Known kinds include schemas, operations,
resources, prompts, workflow values, and effects; unavailable name/argument data
is false rather than inferred. Required-kind errors attach to the supplied source
identifier/context. Documentation covers phases, fields, spaces, and trust limits.

A separate resource-link-tool extension uses only the public API to check its
target and derive descriptive text, then emits core forms retaining arity and
runtime interface checks. The 19 API checks cover imported/local bindings, host
shadowing, separate effect space, workflow values, runtime misuse, source errors,
live resource-link dispatch, and local/imported schema lookup at a shifted phase.
The API/extension/domain suites passed 50 checks before the final shifted-local
assertion; the final API suite passed all 19 checks.

Initial example grammar/literal-context errors were fixed before passing checks.
An initial lookup implementation compiled checked references; a phase probe
exposed an existing failure compiling schema-reference for a schema defined in
begin-for-syntax. Direct binding predicates fix metadata lookup at that phase,
without claiming the separate reference compilation problem fixed. That problem
remains part of the full phase matrix. Complete interface-reference analysis and
the remaining extension/compiler/release gates remain open.

Final validation: sh scripts/check.sh passed compilation, 2,646 native checks,
all 1,301 pinned core schema cases, and Scribble. All five Go probes passed with
sh scripts/check-interop.sh. python3 scripts/package.py rebuilt a clean source
distribution; env -u PLTCOLLECTS raco setup --check-pkg-deps --pkgs racket-mcp
passed in the isolated package environment, including its documentation build.
git diff --check passed. Evidence remains Linux/Racket 9.2; the recorded local
higher-phase reference issue and the full SDK release gates remain open.

## Isolated higher-phase declaration failure (2026-09-07)

Added dev/check-phase-references.rkt as an explicit failing release probe. It
constructs fresh source files and checks ordinary declaration references at phases
0 and 1 in both MCP and a minimal syntax-spec-only language. The independent
language imports no MCP code. Child processes have a 20-second timeout; any failed
case makes the command exit nonzero. This is not an expected-failure unit test and
its failures are not counted as passing SDK evidence.

On Linux/Racket 9.2, both phase-0 cases exit 0 and both phase-1 cases exit 1 with
unbound generated identifiers. The installed syntax-spec-v3 source is pinned to
4ae36610804b58e8f023574bfdcba1b5ae4f7bcd; a live branch query confirmed this is also
the current upstream v3 tip. The development branch uses syntax-spec-dev and is
not a drop-in update. Alternate definition-interface and SDK reference-scope
probes did not fix the failure and were fully removed. No dependency source or
SDK runtime/compiler implementation was changed in this batch.

After restoring the original SDK sources and recompiling, the domain-binding and
extension-binding suites passed 39 checks. The final release probe exits 1, as
recorded above; the phase gate remains failed. The existing passing full suite and
Go runs are historical results, not rerun for this development probe. Declaration
metadata lookup at shifted phases remains covered independently. Documentation
now distinguishes that passing behavior from this unresolved declaration/reference
failure. Other planned implementation work can continue; the SDK goal is neither
complete nor blocked on user input.

## Interface resource-reference validation and composition (2026-09-07)

make-interface now accepts an explicit #:references map from published source
descriptors to referenced resources; interface-resource-references exposes the
normalized immutable map. Target resolution uses resource declaration identity,
not names or URI spelling. Missing sources/targets, invalid target values, and
ambiguous mounted identities fail construction. Duplicate targets normalize once.
Mounts merge maps, views remap surviving sources and target identities, #lang mcp
retains mounted maps, and make-runtime includes them in its validation path.

The new interface-references suite passed 23 checks: tools/resources/prompts,
mutable input-map isolation, removal diagnosis, omission of both endpoints,
namespace/URI transformation, canonical target resolution, live link dispatch
without resource reads, same-name impostors, sibling URI ambiguity, cyclic links,
and module mounts. Existing domain and scoped-view checks passed 41 checks.
A reader typo in the new fixture was corrected before the passing run. Diagnostics
were then expanded to name the source and missing/ambiguous target.

This is the runtime/ordinary-data reference contract. It does not infer handler
references, and automatic compiler collection and static manifest graph emission
remain required. The higher-phase declaration gate and the broader SDK release
requirements remain open.

Final validation: sh scripts/check.sh passed compilation, 2,669 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five official Go SDK probes. git diff --check passed. These results
cover Linux/Racket 9.2; automatic reference inference and the other recorded
release gates remain open.

## Lexical ordinary-handler resource collection (2026-09-07)

Ordinary tool, resource, and prompt handlers now collect resource-name bindings
through syntax-spec's public get-racket-referenced-identifiers API. A private
callable wrapper carries a generated lexical thunk; make-interface resolves it
and combines the targets with explicit reference maps. No handler executes to
discover targets. Tool/prompt bound-argument wrappers retain this metadata.
References resolve after module definitions, including forward declarations,
imports, and macro-generated references; host shadowing and quoted identifiers
produce no edges. Views canonicalize inferred identities just like explicit maps.

The initial probe imported a phase-1 helper at the wrong phase, then analyzed
bodies without their lambda argument scope. Correcting the import and analyzing
the complete lambda resolved both probe failures. Focused existing suites passed
120 checks; inferred-references passed 15 checks, including handler execution
count, forward/imported references, source removal, and live remapped dispatch.
Workflow stages, static manifest edges, separately defined host helpers, and the
higher-phase gate are not established by ordinary-handler collection.

Final validation: sh scripts/check.sh passed compilation, 2,684 native checks,
all 1,301 pinned core schema cases, and Scribble. All five official Go SDK probes
passed via sh scripts/check-interop.sh. A separate local-resource-inside-handler
probe failed with definition-context rejection both with this collector and with
the previous host-interface handler grammar; local DSL declarations are not
claimed as newly supported. Ordinary internal host definitions pass the focused
shadowing checks. Native evidence remains Linux/Racket 9.2.

## Workflow-stage resource-reference collection (2026-09-07)

Generated workflow stage procedures now use the same lexical reference collector
as ordinary handlers. A private structure property lets workflow descriptors
contribute the union of stage references without introducing a descriptor/workflow
module cycle or changing public descriptor constructor arities. Interface
construction combines workflow, ordinary-handler, and explicit references before
identity validation. Discovery resolves only generated binding thunks; it does not
execute stages or acquire storage. Existing emitted-stage fingerprints naturally
change with the generated handler representation, retaining the code compatibility
check rather than silently treating previously compiled stages as identical.

The focused domain-workflow/control-flow/workflow/ordinary-reference suites passed
52 checks. The new workflow-references suite passed 14 checks covering checkpoint,
input, effect-input, branch and completion references; prompt/resource workflows;
workflow argument shadowing; removal rejection; zero execution during construction;
and live remapped link output. An initial fixture used a non-stage set! in a
workflow begin; moving the counter into the final host expression corrected the
fixture before passing validation. Static manifest edges, imported helper body
analysis, the higher-phase gate, and full release verification remain open.

Final validation: sh scripts/check.sh passed compilation, 2,698 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five official Go SDK probes. git diff --check passed. These are
Linux/Racket 9.2 results; the overall SDK release remains incomplete.

## Static lexical resource-reference manifests (2026-09-07)

Resource declaration bindings now carry immutable source/name origin metadata.
The public syntax-spec query preserves it across imports and renames. Owned
handler expansion sends references to the existing per-module lexical collector;
workflow stages use the same path. The finalizer now runs in a final generated
RHS, after application RHS expansion, and syntax-local-lift-module emits an
independent racket/base manifest submodule containing quoted data. Entries record
resource-references and reference-analysis=lexical-handler-syntax. Origins are
deduplicated/sorted; unavailable origin data is explicitly unknown. Runtime
reference maps retain their independent identity checks.

Probes established that use-site syntax properties are discarded by reference
collection, while binding properties survive. A top-level or module-end finalizer
ran too early; module+/module declarations lifted through the generic end-
declaration API were expanded in expression context. A deferred module* could
not access the parent's collector macro with an independent language. Those
prototypes were removed. The final implementation uses the documented dedicated
module-lifting API after RHS expansion and does not inherit the application.

The new manifest fixture has both a throwing application and a throwing imported
provider; reading the manifest succeeds without instantiating either. It checks
renamed and macro-introduced references, forward references, workflow/resource
workflow edges, shadowing, quotes, origin locations, deduplication, and repeat
reads. Its 12 checks pass. Combined focused suites initially reported one wrong
expected source line out of 68 checks; correcting the fixture's line expectation
produced the passing manifest run. Dynamic composition manifests, separately
defined helper analysis, higher-phase support and the broader release gates
remain open.

The first full build and Go run exposed a real matcher defect: server names are
expressions, so free-identifier=? cannot compare every declaration name. The
collector now checks identifier? before comparing owners. Adding a server to the
throwing manifest fixture covers this case; the corrected focused manifest and
compiler suites passed 39 checks. raco mcp inspect examples/multi-content.rkt
shows both tool and prompt edges to pages with original binding source positions.

Final validation: sh scripts/check.sh passed compilation, 2,710 native checks,
all 1,301 pinned core schema cases, and Scribble. The corrected
sh scripts/check-interop.sh run passed all five official Go SDK probes.
git diff --check passed. Verification remains Linux/Racket 9.2; the complete
SDK release gates remain open.

## Manifest-driven interface and workflow diagrams (2026-09-07)

raco mcp diagram now uses manifest->mermaid (also exported from mcp/cli) to show
resource dependencies, workflow entry/sequencing, numbered branches, explicit
joins, terminal completion stages, and effect adapters/policies. Resource edges
require matching name and source with one candidate; external/unresolved and
ambiguous references are labelled rather than silently attached by spelling.
Node IDs are generated; names are encoded as quoted Mermaid labels using decimal
entities, following https://mermaid.js.org/syntax/flowchart. No application runs.

The 25 focused checks independently specify branch/join/terminal edges, adapter
policy, local/foreign/ambiguous resource targets, deterministic output, hostile
label escaping, invalid workflow targets/duplicate IDs, and diagrams read from
a manifest whose parent raises if instantiated. The local mmdc executable is
unavailable; native tests verify text semantics, not rendered Mermaid output.
Dynamic composition graphs and remaining complete tooling/release gates remain
open.

Independent parser validation: installed mermaid 11.17.2 and jsdom 30.0.1 into
ignored .cache/mermaid-check with --ignore-scripts (no global or SDK dependency).
On Node 26.8.1, mermaid.parse accepted five flowchart-v2 artifacts: approval,
resource references, authored branch/join graph, hostile labels, and the rich
throwing-parent manifest. npm emitted extraction ENOENT warnings but exited 0;
actual imports and all five parser calls succeeded. This establishes parser
acceptance, not browser layout or rendered appearance.

Final validation: sh scripts/check.sh passed compilation, 2,735 native checks,
all 1,301 pinned core schema cases, and Scribble. All five Go SDK probes passed
with sh scripts/check-interop.sh. git diff --check passed. Native verification
remains Linux/Racket 9.2; the overall SDK release is incomplete.

## Manifest-driven interface documentation (2026-09-07)

raco mcp docs now renders known manifest data instead of declaring every field
unavailable until runtime. manifest->markdown, exported by mcp/cli, accepts a
manifest and optional title. It includes descriptions, sorted metadata, required/
optional arguments, defaults/codecs, JSON schemas (including their authored
examples), completion targets, lexical resource references, workflow stages and
effect policies, and runtime requirements. Dynamic expressions are labelled and
never evaluated. Generated code spans/fences preserve delimiter-bearing content;
descriptions are escaped as text.

The 27 focused checks cover throwing-parent inspection, required/optional/false
values, dynamic expressions, resource references, completion, workflow details,
stable output, hostile names/descriptions, code fences, and argument validation.
An expected raw mime-type heading initially omitted Markdown's escaped hyphen;
correcting that fixture produced the passing focused suite. Using the existing
ignored parser cache, marked 16.4.2 plus jsdom 30.0.1 independently parsed both
rich and hostile generated documents; heading counts, literal expressions and
backticks, escaped metadata labels, and absence of script elements passed. This
is parsed-document evidence, not browser visual review. No JavaScript dependency
was added to the native SDK. Full authored scenario documentation and dynamic
composition/complete API/release gates remain open.

Final validation: sh scripts/check.sh passed compilation, 2,762 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five Go SDK probes. git diff --check passed. These results cover
Linux/Racket 9.2; the complete SDK release remains unfinished.

## Static contract and workflow compatibility reports (2026-09-07)

manifest-diff now compares deterministic published-identity maps, treating tools
and workflow tools as the same wire identity and rejecting duplicate identities.
It reports changed/unchanged fields and reasons for removals, newly required
arguments, and changed known published resource URIs/templates. Other static
changes require review. Compiler-owned source positions are ignored explicitly
at declaration/stage/reference boundaries; schema data is never recursively
stripped by matching field spelling. Reference provider sources remain identity
evidence. Each report states behavior=not-compared.

Workflow results distinguish known incompatible versions, workflow addition/
removal, and changed stages. Equal stage metadata reports not-established-from-
manifest, never executable compatibility. No arbitrary schema subsumption or
handler equivalence is inferred. The CLI self-diff of examples/approval.rkt
produces unchanged static fields while retaining that workflow limitation.

The focused diff/completion suites passed 53 checks covering source relocation,
application schema fields named source, required/optional changes, metadata/schema
review, URI changes, versions/stages, tool/workflow identity, reference provider
identity, duplicate rejection, stable order, and JSON encoding. An initial stale
compiled export mismatch was resolved by recompiling dependent modules; an initial
fixture parenthesis error was fixed before these passing runs. Full executable
fingerprints, dynamic interface comparison and the remaining release gates stay
open.

A final reporting audit added a guard for incomplete older/dynamic argument
metadata: absence of an arguments list or required flag is not evidence of an
optional argument. Such cases require review rather than claiming a proven new
requirement. The expanded diff suite passed all 28 checks. The preceding full
run passed 2,788 native checks, 1,301 core schema cases, and Scribble; it preceded
this final guard and is not the final-state full-suite result.

Final validation: sh scripts/check.sh passed compilation, 2,790 native checks,
all 1,301 pinned core schema cases, and Scribble after the missing-metadata guard.
All five Go probes passed during this change before that CLI-only guard.
python3 scripts/package.py rebuilt a clean distribution, and the isolated
env -u PLTCOLLECTS raco setup --check-pkg-deps --pkgs racket-mcp passed against
that distribution, including its documentation build. git diff --check passed.
Native evidence remains Linux/Racket 9.2; full release gates remain open.

## Tool boolean schemas and wire-schema parity (2026-09-07)

A descriptor audit found that explicit #:output #f was silently treated as
omission and #:output #t would be advertised as an invalid wire schema. The
pinned core Tool definition requires schema objects (input additionally requires
root type object). make-tool and tool now distinguish omission with missing,
lower true/false output schemas to equivalent objects, and retain #f as the
normalized descriptor's absent-output representation. Upstream adapters pass
missing when outputSchema is absent. Successful results still validate against
the normalized contract; execution-error results remain exempt.

Boolean custom input schemas lower over the JSON-object domain; supplied schema
objects must explicitly declare type object. make-interface checks that same
input/output representation and header-annotation validity for raw descriptors.
No wire boolean schema is emitted. The native general schema evaluator retains
its existing full boolean-schema semantics.

Existing core/upstream/declaration suites passed 143 checks. The new 34 checks
cover omitted/explicit/dynamic schemas, one-time declaration evaluation, scalar
false/null outputs, impossible success versus explicit errors, blocked input
before handler execution, raw descriptor/schema/header rejection, and validation
of every advertised fixture tool against the pinned core Tool schema. Initial
fixture parenthesis errors were corrected before passing runs. Full constructor
parity and the broader release gates remain open.

Final validation: sh scripts/check.sh passed compilation, 2,824 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five Go SDK probes. git diff --check passed. Evidence remains
Linux/Racket 9.2; the complete SDK release gates are still open.

## Arbitrary raised values at protocol, task, and transaction boundaries (2026-09-07)

A probe confirmed that a raised symbol escaped dispatch-message instead of
producing a terminal response. A private non-break failure predicate now handles
arbitrary raised values at the wire boundary and task worker boundary. Protocol
errors remain generic and do not expose payloads; task failures become terminal
and manual effect intents remain recovery-required. Notification and post-commit
publication failures are deferred even for non-exception payloads, without
calling their custom printers. Runtime construction cleanup also rethrows any
raised value after shutting down its allocated custodian. Break exceptions retain
their prior propagation/control meaning.

The regression exposed a storage defect: db's call-with-transaction catches exn?
only, so a non-exception notification failure left an open transaction. The
source confirmed that handler boundary. store-transaction now privately wraps
non-exception values across the database helper to trigger rollback, then raises
the original object. Nested store transactions preserve their shared boundary.

The raised-value, workflow-freshness and stdio-cancellation suites passed 116
checks after recompiling stale dependent storage exports. New cases cover false,
symbol, vector, an unprintable structure, base exn, and break identity; terminal
wire responses and same-connection slot reuse; task failure and manual recovery
without replay; deferred outbox publication; memory/file transaction rollback,
original payload identity, subsequent commit, and reopen persistence. Forced
thread/process termination and the full lifecycle/release matrix remain separate
open gates.

Final validation: sh scripts/check.sh passed compilation, 2,888 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five Go SDK probes. git diff --check passed. Verification remains
Linux/Racket 9.2; remaining lifecycle and full SDK release gates stay open.

## Store-owned transaction cleanup (2026-09-07)

A forced-worker probe showed that kill-thread left both the SQLite transaction
and store semaphore held: Racket does not run the killed thread's dynamic-wind
post thunk. Factory-created stores now retain a supervisor custodian. Each
transaction supervisor owns the managed db transaction and semaphore while the
application callback remains in its original thread and parameterization. Worker
death requests rollback; ordinary completion commits before returning values.
Arbitrary raised values retain their identity without crossing db's exception-only
handler. This supersedes the preceding raised-value wrapper implementation.

Reentrant ownership now includes thread identity, so inherited child-thread
parameters cannot bypass serialization. Queued cancellation observes the finished
signal without waiting for the lock. Managed transaction ownership prevents an
application callback from committing the SDK boundary early. Failed-transaction
connection checks occur before releasing the lock, avoiding interference with a
subsequent transaction. Raw state-store construction uses the caller custodian;
independent supervision is provided by the store factories.

The new termination suite covers memory/file stores, worker kill, request
custodian shutdown, break, escape and prompt abort, unclosed nested transactions,
subsequent bounded reuse, inherited child ownership, queued cancellation,
prohibited early commit, multiple values, nested success, and file reopen.
The 69 new checks and 64 arbitrary-raised-value checks passed together. Before
the final lock-order adjustment, the full run passed 2,957 native checks,
1,301 pinned schema cases, Scribble, and all five Go probes. Final-state results
are recorded below. Full process/crash/commit and store-opening/shutdown races
remain separate release gates.

Final validation: sh scripts/check.sh passed compilation, 2,957 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five Go SDK probes. python3 scripts/package.py rebuilt the clean
source distribution; isolated env -u PLTCOLLECTS raco setup --check-pkg-deps
--pkgs racket-mcp passed including documentation. The first package build caught
an overlong generated section filename; an explicit short Scribble tag fixed it
before the passing build. git diff --check passed. Linux/Racket 9.2 remains the
verified platform; the complete SDK release remains unfinished.

## Shared logical time for authored interactions (2026-09-07)

Scenario preparation found independent wall-clock reads across runtime policy,
durable execution and storage. mcp/clock now provides current-mcp-clock,
mcp-current-milliseconds/seconds, and an exact-capable thread-safe manual clock.
make-runtime captures an explicit/default clock without changing the public raw
runtime constructor arity. Dispatch, HTTP authentication, detached task workers,
startup recovery, repaired-task retries and change publication select that clock.
Default resource caches and pagination share it. Explicit existing per-helper
clock/cache overrides remain supported in their original units.

Workflow/render expiry, task timestamps/expiry, principal checks, journal entries
and outbox retention now use logical time. OAuth helper defaults use the parameter;
HTTP response dates and real scheduling/deadline alarms remain wall-clock based.
This enables deterministic time advancement, not deterministic thread scheduling.
The full scenario fault-injection grammar remains a required implementation item.

The new clock suite passed 52 checks: exact subsecond time, invalid inputs,
concurrent advances, caller/runtime isolation, nested resource render expiry,
cache TTL and cursor expiry, task timestamps and completion, journal/outbox time,
live protected HTTP authentication at the expiry boundary, store reopen, and
startup recovery of a killed working task. An initial test had mismatched
parentheses and used HTTP outcomes without unwrapping the JSON-RPC result; both
were corrected before passing. The preceding focused suites passed 175 checks
before the three startup-recovery assertions were added. A runnable authored
cache-expiry example accompanies the public clock documentation.

The example's first package check rejected a root-level RackUnit import as an
undeclared runtime dependency. Moving it into a user module+ test exposed two
existing scenario defects: #lang mcp generated a test-local mcp-interface that
shadowed the parent before initialization, and the scenario CLI returned zero
after RackUnit reported that error. The example now uses local-require inside
the scenario body. Its final raco test run passes one authored test case (three
assertions), and the CLI run emits no errors. General user-written module+
behavior and failure exit propagation remain explicit scenario gates, not
claimed fixed by the example adjustment.

Final validation: sh scripts/check.sh passed compilation, 3,009 native checks,
all 1,301 pinned core schema cases, and Scribble. sh scripts/check-interop.sh
passed all five official Go probes. The corrected example passed raco make,
raco test and the scenario command separately after the test-import adjustment.
python3 scripts/package.py rebuilt the final clean distribution; isolated
env -u PLTCOLLECTS raco setup --check-pkg-deps --pkgs racket-mcp passed, including
documentation. git diff --check passed. Verification remains Linux/Racket 9.2;
full scenario, compiler and release gates remain open.
