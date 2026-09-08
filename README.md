# Native Racket MCP and `#lang mcp`

Implementation in progress for MCP **2026-07-28**, targeting Racket **9.2**.
This is not yet the completed seven-milestone release. See
[IMPLEMENTATION.md](IMPLEMENTATION.md) for remaining work and validation evidence.

```racket
#lang mcp
(server #:name "greeter" #:version "0.1.0")
(tool (greet [name String])
  #:description "Greet someone by name."
  (text-result (string-append "Hello, " name)))
```

## Run from this checkout

```sh
. scripts/racket-env.sh
raco make examples/greeter.rkt
racket examples/greeter.rkt
racket examples/approval.rkt --state .cache/approval.sqlite
```

The environment script isolates Racket packages and scratch files in this
checkout. Install the pinned language dependency in that environment:

```sh
python3 scripts/prepare-syntax-spec.py
env -u PLTCOLLECTS raco pkg install --name syntax-spec-v3 --auto --batch --no-docs \
  --link "$PWD/.cache/patched-dependencies/syntax-spec-v3"
python3 scripts/package.py
env -u PLTCOLLECTS raco pkg install --name racket-mcp --no-setup \
  --link "$PWD/.cache/distribution/racket-mcp"
```

The preparation command verifies the vendored upstream hashes and applies the
SDK's module-binding phase and reference-registration fixes to a separate local
copy (version 0.1.0.2). It
does not fetch sources or modify a globally installed package. If this checkout
already has the original dependency installed, use `env -u PLTCOLLECTS raco pkg update --batch
--no-setup --name syntax-spec-v3 --link
"$PWD/.cache/patched-dependencies/syntax-spec-v3"` after preparation. Run these
commands with `scripts/racket-env.sh` sourced as above. The unpatched upstream
0.1 package does not satisfy the SDK dependency requirement.

Native CI uses `python scripts/ci.py` with an existing Racket installation. This
portable runner prepares the pinned language dependency, keeps package writes in
`.cache/ci/package-home`, and runs compilation, the native and pinned schema
suites, documentation, and package dependency checks. It saves command logs and
`report.json` in `.cache/ci/results`. For an already bootstrapped local checkout,
use `python3 scripts/ci.py --skip-bootstrap --package-home .racket`.

The shell check scripts use `.racket` by default. Set `MCP_RACKET_USER_HOME` to
an explicit project-local package home when checking another Racket installation;
for example, use the same home passed to `scripts/ci.py --package-home` when
running `scripts/check-interop.sh` with that Racket's `bin` directory on `PATH`.

The GitHub Actions matrix targets x64 Linux, macOS, and Windows with Racket 9.2
and 9.3 (the current stable release when configured). Action revisions and Racket
versions are pinned in `.github/workflows/native.yml`. CI runs are evidence for
their reported platform/version and revision only; workflow presence is not a
passing release claim. Go interoperability and the full MCP conformance harness
remain separate checks.

Local Linux x86_64 verification passed on Racket 9.2 and 9.3. The latest full
Racket 9.3 run passed 5,953 native checks, 1,301 pinned core schema cases,
86 optional regex cases, documentation, package checks and all fourteen Go probes;
see `test-artifacts/native-executable-20260908`. The full 9.2 run at
017af62 passed 5,785 native checks, the core and optional regex suites, and
Scribble. The subsequent reference-compiler dependency fix passed the full 9.3
run and focused source-only checks on 9.2; no newer full 9.2 run is claimed.
The native total includes 242 pinned format cases tested
through the separate MCP elicitation assertions. Five targeted independent MCP
scenarios also passed all 16 checks; this is not full conformance.
The earlier fresh 9.3 dependency bootstrap exposed an omitted development fixture
retaining 9.2 bytecode. Validation scripts now compile every top-level development
fixture; `test-artifacts/linux-9.3-current-20260907` retains that failure and fix.
The first hosted matrix run was prevented from starting by an Actions budget;
macOS and Windows remain unverified. See `test-artifacts/native-platform-2026-09-07`
and the implementation ledger for the version-specific evidence.

The CLI is also available without package registration:

```sh
racket -l mcp/cli -- inspect examples/library.rkt
racket -l mcp/cli -- --transport http --port 8000 serve examples/greeter.rkt
racket -l mcp/cli -- --state .cache/approval.sqlite serve examples/approval.rkt
```

Options currently precede the command. Stdio defaults to newline-delimited UTF-8
JSON. HTTP binds to 127.0.0.1 by default. No initialization handshake or MCP
session identifier is used. Application definitions retain normal Racket module
instantiation semantics; importing a descriptor does not start a transport.

For captured workflow loading, supply an immutable identity for your SDK and
Racket runtime distribution:

```sh
raco mcp --runtime-build-id MY-IMMUTABLE-RUNTIME-BUILD --state state.sqlite serve application.rkt
```

The library equivalent is `(load-interface path #:runtime-build-id id)`, available
from `mcp` and `mcp/loader`. It returns native SDK descriptors and rejects changed
captured helpers on resume. The ID is supplied by the application owner; automatic
runtime provenance and conversion of the default/direct loading path remain open.
The manual's “Loading interfaces with executable identity” section explains the
contract, cache limitations, and prepared dynamic imports.

## Implemented paths

- Tool, resource, prompt, shape, schema, completion, and staged workflow
  declarations, including resumable conditionals, matches, and lexical blocks; ordinary Racket
  constructors expose the same runtime values.
- Required, optional, and default arguments. Defaults run left-to-right once for
  absent arguments and can refer to preceding arguments. `missing`, `'null`, and
  `#f` are distinct.
- Exact JSON decimals and a native schema evaluator passing the pinned 1,301-case
  core JSON Schema 2020-12 suite, including local/registered references, dynamic
  anchors, and unevaluated annotations. This does not establish complete
  ECMAScript regex or optional format-assertion compatibility.
- Local dispatch, concurrent stdio client/server, HTTP JSON/SSE client/server,
  parameter headers, capability/version checks, progress, and subscriptions.
- SQLite checkpoints, effect intents, explicit manual recovery, task polling and
  input updates; MRTR interaction callbacks. Memory storage is ephemeral SQLite.
- Resource references, URI expansion, links/embeddings, interface mounting/views,
  private-cache/outbox primitives, and authorization adapters/PKCE functions.
- Independently loadable manifests; CLI inspection, diagrams, basic docs,
  expansion checks, test-submodule scenarios, snapshots, and conservative diffs.
- A separately implemented `collection` extension in `examples/extensions`.

## Validation

```sh
. scripts/racket-env.sh
raco make mcp/*.rkt examples/*.rkt tests/*.rkt
raco test tests
racket tests/schema-suite.rkt
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl
```

Run `sh scripts/check-interop.sh` for fourteen pinned official Go SDK probes: basic
discovery/tool calls, pagination, multi-content resource/prompt/tool rendering,
the separate collection extension’s generated search/resource/completion interface,
and progress/cancellation in both client/server directions. Cancellation probes verify that the remote handler actually stops
and the same connection accepts another request. Go is a development dependency;
binaries and build caches stay under `.cache`.

HTTP tests require permission to bind ephemeral loopback ports. The official Go
SDK probe is in `dev/interop`; its dependencies and the conformance harness are
development inputs only. The SDK runtime is Racket. `vendor/LOCK.json` records
upstream commits and file hashes. Refreshing inputs is an explicit networked
maintenance operation: `python3 scripts/fetch-inputs.py [source ...]`.

Do not infer release completeness from the passing core tests. The implementation
ledger records missing language semantics, recovery races still needing tests,
conformance exclusions, and unavailable native platform verification.
