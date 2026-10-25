# racket-mcp

An experimental Racket SDK and `#lang mcp` for building **Model Context Protocol
(MCP) clients and servers**. Define tools, resources, and prompts in Racket, or
build SQLite-backed workflows that pause for input and resume after a restart.

The language supports ordinary Racket definitions, imports, and macros. You can
also construct the same server descriptions through the SDK without using
`#lang mcp`.

This version implements the pinned **MCP 2026-07-28** protocol. It uses per-request
metadata rather than an initialization handshake or session identifier; clients
must support that protocol. **Linux x86_64 with Racket 9.2 and 9.3 is verified.**
macOS and Windows are unverified. See [status and limitations](#status-and-limitations)
before choosing it for an application.

## Try your first tool

You will install the SDK in a checkout, run the included greeting server, and
call its `greet` tool. You need Racket 9.2 or 9.3 with `raco`, Python 3, and a
POSIX shell. Run the shell commands from the repository root in the same terminal.
These instructions assume a fresh checkout.

### 1. Install the local packages

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

The environment script keeps package state in `.racket` and scratch files in
`.cache`. Preparation verifies the bundled language dependency and patches a
separate local copy; it does not alter the vendored source or global packages.
The final setup command registers `raco mcp`.

### 2. Read and start the server

[examples/greeter.rkt](examples/greeter.rkt) is the complete server:

```racket
#lang mcp
(server #:name "greeter" #:version "0.1.0")
(tool (greet [name String])
  #:description "Greet someone by name."
  (text-result (string-append "Hello, " name)))
```

Compile it, then start it:

```sh
raco make examples/greeter.rkt
racket examples/greeter.rkt
```

The server waits for JSON requests on standard input. It does not display a prompt.

### 3. Call the tool

Paste this **single line** into the running server and press Enter. It asks the
`greet` tool to greet Ada and supplies the protocol metadata required by this version.

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"greet","arguments":{"name":"Ada"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
```

The server returns a JSON response with request ID `1` and a text content item
containing **`Hello, Ada`**. Change the name to `Grace` and the request ID to `2`,
then send the line again to receive `Hello, Grace`.

Press **Ctrl+D** on an empty line to close standard input and return to your shell.
You have defined a tool and called it over the SDK's newline-delimited JSON transport.

## Build something of your own

The SDK includes schemas and typed declarations, asynchronous clients, HTTP
JSON/SSE transports, progress and subscriptions, interface composition, and
OAuth helpers. Durable workflows add checkpoints, task polling, input updates,
and explicit recovery for uncertain effects. An in-memory store uses ephemeral
SQLite; a file-backed store preserves state across restarts.

Choose an example or document for your next task:

| I want to… | Start here |
| --- | --- |
| Pause a workflow for approval | [Approval example](examples/approval.rkt); run `racket examples/approval.rkt --state .cache/approval.sqlite` |
| Compose an interface | [Library example](examples/library.rkt); inspect it with `raco mcp inspect examples/library.rkt` |
| Serve over HTTP | Run `raco mcp --transport http --port 8000 serve examples/greeter.rkt`; it binds to `127.0.0.1` by default |
| Extend the language | [Collection extension](examples/extensions/collection.rkt) |
| Configure OAuth client registration | [Registration API and supported metadata](OAUTH-REGISTRATION.md) |
| Understand the persistence design | [SQLite persistence comparison](reports/MCP%20SDK%20persistence%20comparison.md) |
| Look up declarations, APIs, and recovery rules | [Scribble manual source](mcp/scribblings/mcp.scrbl) |

Run each server example separately and stop it before starting another. CLI options
precede the command. Without package registration, use `racket -l mcp/cli --`
in place of `raco mcp` in the same checkout environment.

To build a browsable copy of the manual:

```sh
raco scribble +m --htmls --dest .cache/manual mcp/scribblings/mcp.scrbl
```

Open `.cache/manual/mcp/index.html`. For workflows that must survive application
updates, read “Loading interfaces with executable identity” and “Declared identities
for ordinary loading” in the manual before deploying changes. The application supplies and
maintains its build identity; ordinary loading does not infer it automatically.
Importing a server description does not start its transport, but ordinary Racket
module definitions still execute when the module is instantiated.

## Work on the SDK

After the setup above, run the native verification suite:

```sh
python3 scripts/ci.py --skip-bootstrap --package-home .racket
```

It runs compilation, native tests, schema and regex suites, the manual build, and
installed-package dependency checks. Logs and `report.json` are written to
`.cache/ci/results`. To exercise an independent package bootstrap, use
`python3 scripts/ci.py` with its default `.cache/ci/package-home`.

Go is needed only for the separate interoperability probes:

```sh
sh scripts/check-interop.sh
```

HTTP tests bind ephemeral loopback ports. When using another package home, set
`MCP_RACKET_USER_HOME` to that same directory for the shell check scripts and put
the desired Racket installation's `bin` directory on `PATH`. The full MCP
conformance harness is a separate development check; see the
[validation record](test-artifacts/public-readiness-20261025/README.md) and
[OAuth fixture preparation](CONFORMANCE-FIXTURE.md).

<details>
<summary>Update a checkout with the older language dependency</summary>

The SDK requires the prepared `syntax-spec-v3` version `0.1.0.2`; the unpatched
upstream `0.1` package does not satisfy that requirement. With the checkout
environment sourced, prepare the dependency and update its existing registration:

```sh
. scripts/racket-env.sh
python3 scripts/prepare-syntax-spec.py
env -u PLTCOLLECTS raco pkg update --batch --no-setup --name syntax-spec-v3 \
  --link "$PWD/.cache/patched-dependencies/syntax-spec-v3"
```

Then rebuild the distribution with `python3 scripts/package.py` and register its
commands with `env -u PLTCOLLECTS raco setup --no-zo --no-docs --pkgs racket-mcp`.

</details>

Vendored commits and file hashes are recorded in [vendor/LOCK.json](vendor/LOCK.json).
Updating them is an explicit networked maintenance operation through
`scripts/fetch-inputs.py`; normal preparation uses the bundled source.

## Status and limitations

The October 25, 2026 validation passed on both Linux/Racket versions: **6,852 native
tests, 1,301 schema cases, 86 regex cases, 14 Go interoperability probes, and 38
selected installed-package checks per version**. Fresh installation, compilation,
manual generation, and package dependency checks also passed. Detailed commands,
source hashes, and archive comparisons are in the
[validation record](test-artifacts/public-readiness-20261025/README.md).

This remains an experimental SDK with **qualified MCP conformance**. Core, Tasks,
and OAuth checks retain documented failures, warnings, or skips. One accepted
Tasks limitation returns an unknown-task error before a missing-capability error
when both conditions apply. The request is rejected in either case; the current
version retains ownership protections and workflow-resumption fixes. Acceptance
does not make the error ordering conformant, and a later fix must preserve those
protections. See [current limitations and their rationale](REMAINING.md).

Schema validation does not claim complete ECMAScript regex or optional
format-assertion support. Hosted GitHub Actions are disabled; native macOS and
Windows execution remains unverified. [IMPLEMENTATION.md](IMPLEMENTATION.md)
preserves the development history; its older entries are not the current work list.

## License

Original code and documentation are [MIT-licensed](LICENSE). Bundled third-party
material and derived extracts retain their own terms; see
[third-party notices](THIRD-PARTY-NOTICES.md).
