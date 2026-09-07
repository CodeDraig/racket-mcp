# Implementation and evidence ledger

Target: MCP 2026-07-28; Racket 9.2. Evidence date: 2026-09-07.
**The requested seven-milestone release is incomplete.** This checkout contains a
working development implementation, not a release-level conformance claim.
Passing a fixture does not establish every behavior of an advertised facility.

## Milestones

| Milestone | Delivered | Remaining gate |
|---|---|---|
| 1. Foundation and vertical slice | Package, reader, ordinary Racket definitions, descriptors, local and stdio tools, pins | Private normalized IR and complete binding classes are incomplete |
| 2. Schemas and declarations | Native schema evaluator; shapes; resources, prompts, completion; negative syntax tests | Full schema-construction checks, pattern coverage, string codecs, durable embedding |
| 3. Protocol SDK | Client/server stdio and HTTP JSON/SSE; discovery; header checks; subscription broker; authorization functions | Complete transport ownership, pagination policy, authorization flow integration, conformance coverage |
| 4. Durable interactions | SQLite stages, effects, MRTR, explicit recovery, task polling/update/cancel | Full workflow grammar, concurrent recovery arbitration, automatic task restart, task notifications, nested MRTR |
| 5. Interface integration | Mounts/views, reference remapping, upstream tools, cache/outbox primitives, separate extension example | Authorization/adapter transformations, dependency declarations, upstream MRTR/Tasks translation |
| 6. Developer experience | All named CLI commands have implementations; manifests, Scribble, examples | Complete manifests/diagrams/docs, scenario fault DSL, binding-aware extension API |
| 7. Release verification | Linux 9.2 tests, pinned schema suite, independent MCP checks, Go SDK probe, package checks | Full applicable conformance, other platforms/releases, all acceptance cases |

## Requirement-to-test ledger

“Covered” below means the named behavior has executed tests; it does not imply
complete coverage of its surrounding milestone.

| Requirement | Implementation and evidence | Status / limitation |
|---|---|---|
| Reader, module imports/exports, executable server, fragment | `mcp/lang.rkt`, `mcp/lang/reader.rkt`; `tests/core.rkt`, executable examples | Covered basic behavior; extension-generated server entry points incomplete |
| Required/optional/default arguments; omitted/null/false | `descriptor.rkt`, `forms.rkt`; `tests/core.rkt` | Covered defaults, order/count, distinct representations |
| Duplicate binders and resource-reference arity | `forms.rkt`, private resource binding; core/domain tests | Covered source-attached expansion errors; complete phase/hygiene matrix outstanding |
| Macro and data API share runtime values | `descriptor.rkt`, generated handlers; core/domain/upstream tests | Implemented; constructor checks are not yet fully equivalent for every declaration |
| syntax-spec-v3 | Private handler host interface | Used for handler bindings; separate schema/resource/operation/effect/workflow binding classes still required |
| Public extension API | `define-mcp-extension`, `examples/extensions/collection.rkt`, compiler tests | Declaration macro extension works; full binding API and workflow extension hooks missing |
| Manifest without parent instantiation | Private collector/finalizer, `cli.rkt`; throwing parent fixture in compiler tests | Covered; manifest currently omits most schemas/contracts/capabilities/references |
| Exact JSON, bounds, duplicate keys | `json.rkt`; core/schema tests | Implemented; direct streaming decoder counts characters rather than UTF-8 bytes; transports separately bound frames |
| JSON Schema 2020-12 core suite | `schema.rkt`, private pattern layer; `tests/schema-suite.rkt` | 1,301 pinned core cases passed; no failed/skipped core cases |
| References and annotations | Local registry, anchors, dynamic refs, unevaluated properties/items | Covered by official core cases, including local remote fixtures; no network fetching |
| Schema dialect/vocabulary rejection | Native evaluator and core tests | Implemented; complete malformed-schema/meta-validation still needed |
| Regex and optional format assertions | Private pattern compatibility layer | Partial; official optional cases not counted in the 1,301 result |
| Shapes and codecs | Generated constructor/accessors/JSON codecs; domain tests | Required fields implemented; general persistent codec registry missing |
| Resources, RFC 6570, links, embeds | `descriptor.rkt`, `uri-template.rkt`, `runtime.rkt`; domain tests and MCP fixtures | Text/binary and remapped reference identity covered; ambiguous URI overlap analysis incomplete |
| Prompts and completion | Runtime, composition, completion descriptors; domain and MCP fixtures | Wire strings and multi-content role lowering; renamed/removed completion targets covered; explicit string-codec syntax missing |
| Nested input-required rendering | None | Missing persistent parent rendering, child input namespaces, retained child results |
| Discovery and capability/version metadata | `runtime.rkt`; core and official stateless checks | Covered tested paths; no initialization/session state; complete facility-derived advertisement audit outstanding |
| JSON-RPC envelopes and errors | Runtime and transport modules; core and wire-schema checks | Tested envelopes and current error allocations; full notification direction and malformed-envelope matrix outstanding |
| Stdio concurrency/cancellation | `stdio.rkt`; core tests, official Go SDK probe | Bounded reader/workers/writer; EOF cleanup, client reader/port ownership, progress demultiplexing need more work |
| HTTP JSON/SSE and headers | `http.rkt`, `header-schema.rkt`; HTTP/header tests, independent scenarios | Tested versions/names/Unicode/annotated parameters and root URLs; keep-alives, bounded SSE frames, disconnect/cancellation races outstanding |
| Subscriptions | `subscription.rkt`; subscription tests and runtime integration | Ack order, filter routing, overflow, closure tested locally; full HTTP reconnect/filter-validation coverage missing |
| Pagination and caching fields | Runtime zero-TTL private results; upstream pagination | Cache fields pass fixtures; server cursor/pagination policy and custom cache declarations incomplete |
| Authorization | `authorization.rkt`; authorization/header tests | Verified principal, scope checks, issuer/resource-scoped OAuth helpers and PKCE; complete HTTP metadata routes/discovery/browser/credential flow integration missing |
| Checkpoints and branches | `workflow.rkt`, generated explicit stages; workflow/branch tests | Sequencing and tail if/match covered; non-tail control flow and suspending lexical blocks missing |
| MRTR state and input | Workflow/store and `interaction.rkt`; workflow and official MRTR fixtures | Opaque handles, ownership/arguments/expiry/code checks, sequential input; same handle reused across rounds, multi-input batching missing |
| SQLite durability and recovery | `storage.rkt`, `workflow.rkt`; workflow/restart tests | Real child-process crash/manual recovery tested; full every-boundary concurrent/crash matrix missing |
| Effect policies | Transactional, idempotent, manual adapters; workflow/restart tests | Explicit intents and journaled recovery; manual in-flight arbitration/leases and concurrent recovery races still need work |
| Workflow executable compatibility | Version and source-form fingerprint stored | Imported helper changes are not included in build fingerprint; complete executable compatibility gate missing |
| Tasks | `tasks.rkt`; tasks tests | Persist-before-return, polling, input update, owner checks, terminal immutability; task workers detached from request cancellation/output |
| Task restart and notifications | Explicit `resume-task!` | Automatic scanning/claiming and opted-in notifications missing; repaired failed task gets no automatic new handle |
| Interface views | `composition.rkt`; domain tests | Inclusion/exclusion/namespaces/names/URI mapping; completion and link names remap; restrictive authorization/effect views missing |
| Upstream adapters | `upstream.rkt`; upstream tests | Pinned snapshots, compatibility check, full input schemas for tools; resources/prompts and durable MRTR/Tasks translation missing |
| Freshness | `freshness.rkt`; freshness tests | Private cache and SQLite outbox primitives; `#:depends-on`/`#:changes`, automatic runtime invalidation/commit hooks missing |
| CLI and authored scenarios | `cli.rkt`; compiler tests, executable examples | Basic commands; scenarios run test submodules only; deterministic fault-injection scenario language missing |
| Documentation and package | Scribble manual; isolated package registration and setup | Linux build and package dependency checks passed; complete API reference and native platform checks outstanding |

## Independent validation

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
| input-required-result-multiple-input-requests | Harness fixture requires sampling and roots as well as elicitation; excluded mixed-method fixture. Multiple elicitation requests remain an unimplemented acceptance case |
| input-required-result-capability-check | Harness specifically requests a sampling-only interaction; excluded fixture. Native missing-capability behavior is tested independently |
| input-required-result-multi-round | Missing fixture and evolving request-state implementation; sequential stages exist but this acceptance case is unfinished |
| input-required-result-non-tool-request | Missing prompt/resource MRTR implementation |

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
  Racket release were unavailable and are unverified. No Git repository existed,
  so `git diff --check` could not be used. No commit or global package installation
  was performed.
