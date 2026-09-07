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
```

The environment script isolates Racket packages and scratch files in this
checkout. Install the pinned language dependency in that environment:

```sh
raco pkg install --name syntax-spec-v3 --auto --batch --no-docs \
  'https://github.com/michaelballantyne/syntax-spec.git#4ae36610804b58e8f023574bfdcba1b5ae4f7bcd'
python3 scripts/package.py
env -u PLTCOLLECTS raco pkg install --name racket-mcp --no-setup \
  --link "$PWD/.cache/distribution/racket-mcp"
```

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

## Implemented paths

- Tool, resource, prompt, shape, schema, completion, and staged workflow
  declarations, including tail-position conditionals and matches; ordinary Racket
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

HTTP tests require permission to bind ephemeral loopback ports. The official Go
SDK probe is in `dev/interop`; its dependencies and the conformance harness are
development inputs only. The SDK runtime is Racket. `vendor/LOCK.json` records
upstream commits and file hashes. Refreshing inputs is an explicit networked
maintenance operation: `python3 scripts/fetch-inputs.py [source ...]`.

Do not infer release completeness from the passing core tests. The implementation
ledger records missing language semantics, recovery races still needing tests,
conformance exclusions, and unavailable native platform verification.
