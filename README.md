# Native Racket MCP and `#lang mcp`

Original racket-mcp code and documentation are licensed under the [MIT License](LICENSE).
Bundled third-party material and derived extracts retain their respective licenses;
see [third-party notices](THIRD-PARTY-NOTICES.md) for scope, attribution, and license texts.

Native SDK and language for MCP **2026-07-28**, targeting Racket **9.2**.
The approved implementation scope is complete, with qualified conformance results
and Linux verification on Racket 9.2/9.3. Native macOS/Windows testing was removed
from the release plan; those platforms remain unverified. See
[REMAINING.md](REMAINING.md) for mutable remaining work and
[IMPLEMENTATION.md](IMPLEMENTATION.md) for recorded implementation evidence.

```racket
#lang mcp
(server #:name "greeter" #:version "0.1.0")
(tool (greet [name String])
  #:description "Greet someone by name."
  (text-result (string-append "Hello, " name)))
```

## Run from this checkout

Start with Racket installed, then prepare and install the pinned language
dependency before compiling or running an example. The environment script isolates
Racket packages and scratch files in this checkout.

```sh
. scripts/racket-env.sh
python3 scripts/prepare-syntax-spec.py
env -u PLTCOLLECTS raco pkg install --name syntax-spec-v3 --auto --batch --no-docs \
  --link "$PWD/.cache/patched-dependencies/syntax-spec-v3"
python3 scripts/package.py
env -u PLTCOLLECTS raco pkg install --name racket-mcp --no-setup \
  --link "$PWD/.cache/distribution/racket-mcp"
env -u PLTCOLLECTS raco setup --no-zo --no-docs --pkgs racket-mcp
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

After installation, run the examples in the same shell:

```sh
raco make examples/greeter.rkt
racket examples/greeter.rkt
racket examples/approval.rkt --state .cache/approval.sqlite
```

The greeter serves MCP over standard input/output and waits for client requests;
stop it before launching the approval example.

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

The retained GitHub Actions matrix targets x64 Linux, macOS, and Windows with Racket 9.2
and 9.3 (the current stable release when configured). Action revisions and Racket
versions are pinned in `.github/workflows/native.yml`. Hosted Actions are disabled;
native macOS/Windows verification is no longer a release requirement. CI runs are evidence for
their reported platform/version and revision only; workflow presence is not a
passing release claim. Go interoperability and the full MCP conformance harness
remain separate checks.

Final Linux x86_64 checks pass on Racket 9.2 (6,264 native tests) and 9.3 (6,268),
with 1,301 schema cases, 86 regex cases and Scribble on each. Installed-package
dependency validation and 22 selected installed checks also pass on both versions.
Evidence, including the corrected adapter-guard regression and retained failed
attempts, is in `test-artifacts/declared-build-20260908`. Reproducible source-archive
evidence is in `test-artifacts/release-package-20260908`.

All fourteen official Go interoperability probes passed after the identity integration.
Core and Tasks conformance were refreshed with unchanged qualified outcomes in
`test-artifacts/declared-core-20260908` and `test-artifacts/declared-tasks-corrected-20260908`.
The qualified MCP results are in `test-artifacts/conformance-closure-20260908`:
144 core successes with four excluded roots/sampling fixture failures and one
recorded MRTR warning; 43 Tasks successes with a header-specification disagreement
and a harness notification skip; 62 client successes and four expected skips;
and a real HTTPS CIMD/offline-access run with a 12/12 terminal pass. These results
are not an unqualified conformance claim. A later hosted retry was blocked before native jobs started by an Actions budget.
macOS and Windows remain unverified; this is not a remaining release gate.

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
captured helpers on resume. The ID is supplied by the application owner.
The manual's “Loading interfaces with executable identity” section explains the
contract, cache limitations, and prepared dynamic imports.

For ordinary source or compiled loading, declare the identity of your complete
application/runtime build:

```sh
racket application.rkt --build-id my-application/42 --state state.sqlite
```

Use `(make-runtime interface #:store store #:build-id "my-application/42")` in
library code, or `call-with-build-identity` around workflow construction and
low-level execution. The application must update this identity when executable
dependencies change. It is a declaration, not automatic provenance. Changed IDs
reject incompatible workflow, parent-rendering and upstream resumes; ordinary
loading retains normal module-instantiation semantics.

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

Explicit dynamic registration requests and response validation are available in
`mcp/oauth-registration`; see [the API and supported metadata profile](OAUTH-REGISTRATION.md).
Issuer-scoped SQLite persistence, secret expiry, and authorization-server changes
are handled by `mcp/oauth-registration-store`. Opt-in authorizer integration
selects DCR after pre-registration/CIMD and uses issued credentials for native
token exchange and refresh.

The pinned conformance registration fixture has a reproducible local correction.
See [preparation, boundaries, and validation](CONFORMANCE-FIXTURE.md). Prepared
harness results remain explicitly distinct from unmodified conformance credit.
