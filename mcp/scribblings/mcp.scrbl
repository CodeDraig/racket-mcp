#lang scribble/manual
@(require (for-label racket/base (only-in mcp tool schema shape resource text-result structured-result error-result)))
@title{MCP for Racket: Development API}
@author{Racket MCP contributors}

This package targets MCP 2026-07-28 and Racket 9.2. It is an implementation in
progress, not a completed conformant release. The repository implementation
ledger is the authority for missing behavior and executed verification.

@section{A first server}
@tt{#lang mcp}
@racketmod[
mcp
(server #:name "greeter" #:version "0.1.0")
(tool (greet [name String])
  #:description "Greet someone by name."
  (text-result (string-append "Hello, " name)))
]

The language supports ordinary Racket definitions, imports, macros, exports,
and submodules. Every module exports @racket[mcp-interface], an interface
descriptor. A fragment may omit @racket[server]. A server declaration generates
a main submodule; normal descriptor import does not start a server. User-written
module definitions still execute when their module is instantiated.

@section{Declarations and values}
@defmodule[mcp]
@defform[(tool (name [argument schema-expression] ...) body ...)]{
Defines a tool descriptor and registers it with the enclosing language module.
Optional clauses before the body, in order, are @racket[#:description],
@racket[#:output], and @racket[#:annotations]. A required argument has the shown
shape. Append @racket[#:optional] to receive @racket[missing] when absent, or
@racket[#:default expression] for a default. Defaults execute once, left to right,
and can reference preceding arguments. JSON null is @racket['null]; false is
@racket[#f]. Duplicate argument binders are expansion errors.}
@defform[(schema name schema-expression)]{
Defines a reusable JSON Schema. Literal boolean/object schemas receive expansion
checks; dynamic schemas receive construction checks. Arbitrary schema expressions
are never evaluated by a transformer.}
@defform[(shape name [field schema-expression] ...)]{
Produces the schema binding, a @tt{make-name} constructor, @tt{name-field}
accessors, and @tt{name->json}/@tt{json->name} codecs. These generated names use the
declared spelling and lexical context. The initial shape form has required fields.}
@defform[(resource (name [argument schema-expression] ...) #:uri uri-expression body ...)]{
Calling the resource binding constructs a reference, with expansion-time arity
checks. It does not read the resource. Optional clauses are @racket[#:description],
@racket[#:mime-type], and @racket[#:matcher], in that order. A renderer returns a
string or bytes. JSON content is rendered as labelled text, never as a new MCP
content type. Simple templates receive an inverse matcher; ambiguous templates
require an explicit matcher.}
@defproc[(text-result [text string?]) hash?]{Constructs a complete text tool result.}
@defproc[(structured-result [value any/c] [#:content content list? '()]) hash?]{
Constructs a structured result. Successful declared output schemas are checked
before dispatch returns the result.}
@defproc[(error-result [message string?]) hash?]{Constructs an execution-error tool result.}

@racket[link] serializes a reference through the active mounted interface.
@racket[embed] resolves it through the current authorization and dispatch path.
Embedding checks cycles and depth. Durable nested input-required embeddings are
not implemented yet. @racket[role] expands several content items into the required
sequence of single-content prompt messages. Prompt arguments currently use string
schemas; application string-codec declarations remain outstanding.

@section{Workflow execution}
@racketblock[
(workflow (approve [name String]) #:version "1"
  (checkpoint [greeting String] (string-append "Hello, " name))
  (await-input [answer Any]
    (hasheq 'mode "form" 'message "Continue?"
            'requestedSchema (object-schema (hasheq 'approved Boolean))))
  (structured-result (hasheq 'greeting greeting 'answer answer)))
]
The implemented grammar is a sequence of @racket[checkpoint],
@racket[await-input], and @racket[perform] stages, followed by a result expression.
Tail-position @racket[if] and @tt{match} blocks may contain persistent stages.
Decisions and match subjects are persisted. Non-tail control flow and suspending
lexical blocks remain to be implemented.
Host expressions cannot hide suspension forms. Persistent stage values must be
JSON encodable and satisfy the stage schema; ports, closures, and continuations
are not persisted.

An effect stage has the form
@racketblock[(perform [receipt Integer] #:adapter writer #:policy manual input-expression)]
Adapters declare @racket['transactional], @racket['idempotent], or
@racket['manual]. Transactional adapters receive the store connection. Idempotent
adapters receive the saved key across retries. Manual uncertainty requires an
explicit journaled recovery action. A key does not provide exactly-once execution.
@racket[#:execution task] selects Tasks instead of MRTR. Durable serving requires
an explicit state-file configuration. Task restart scanning is not automatic yet;
the runtime exposes explicit task-resume functions.

@section{Transports, policy, and ownership}
@subsection{Stdio}
@defmodule[mcp/stdio]
@racket[make-stdio-client] accepts input/output ports. @racket[client-request]
returns an event-compatible request handle; @racket[client-call] synchronizes it.
The notification channel is bounded. @racket[request-cancel!] signals cancellation.
Stdio has one reader, concurrent bounded workers, and a serialized writer;
handler stdout is routed to the error port.
@subsection{HTTP}
@defmodule[mcp/http]
@racket[make-http-client] and @racket[http-client-request] provide HTTP equivalents.
List tools before calling header-annotated tools, or preload schemas using
@racket[#:schemas]. Invalid header annotations are excluded from HTTP listings.
No standalone GET stream, session ID, or stream resumption is implemented.
Disconnect cleanup and keep-alive behavior still need full acceptance coverage.
@subsection{Authorization}
@defmodule[mcp/authorization]
The server accepts an application token-verification adapter returning a
@racket[verified-principal]. The SDK checks issuer, audience, expiry, and scopes
through explicit APIs. OAuth functions create PKCE requests and validate state and
issuer during exchange. Discovery fetches, exchanges, browser interaction, and
credential persistence remain application callbacks. Hosted authorization services
and dynamic client registration are outside the package scope.

@section{Composition, extensions, and inspection}
@racket[mount] composes descriptors and registers the result in a language module.
@racket[view] supports selection, renaming, namespaces, and simple URI remapping.
Reference identity survives remapping. Authorization transformation and upstream
MRTR/Tasks bridging are not complete.

@racket[define-mcp-extension] currently exposes a declaration macro transformer.
Its output goes through the core declarations and their checks. The separate
@tt{collection} example demonstrates this path. Generated handler bindings use
@tt{syntax-spec-v3}; the planned separate DSL binding classes and workflow extension
hooks are not fully implemented. Compiler modules are private and not an API.

The manifest submodule can be instantiated without the parent application.
It records expanded core declarations and source locations, marking metadata
whose value is dynamic. Compiling a module still executes trusted transformers.
@tt{inspect}, @tt{diagram}, @tt{docs}, @tt{check}, @tt{scenario}, @tt{snapshot}, and
@tt{diff} are available through @tt{raco mcp} after package registration, or
@tt{racket -l mcp/cli --}. Current documentation and compatibility output is basic;
it does not establish arbitrary schema subsumption or handler equivalence.

@section{Verification boundary}
The pinned core JSON Schema suite has 1,301 cases. Passing it does not establish
optional format assertion or complete ECMAScript pattern compatibility.
Independent MCP evidence and exclusions are recorded under @tt{test-artifacts}.
Native macOS, Windows, and additional Racket releases have not been verified in
this Linux workspace.
