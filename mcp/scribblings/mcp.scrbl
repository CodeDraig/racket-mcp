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
accessors, @tt{name->json}/@tt{json->name} conversions, and a @tt{name-codec} binding. These generated names use the
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
Embedding checks cycles and depth. Prompts and resources accept a
@racket[#:workflow "version"] clause after their metadata clauses. Their bodies
then use the workflow stage grammar; a prompt ends with a message list and a
resource ends with its rendered text. The ordinary constructors accept a
@racket[#:workflow] descriptor with @racket[#f] as the unused handler. These
executions share checkpoint and input persistence with tools, and are bound to
the request method. When a store is configured, embedded content in tool/prompt results is captured as
a persistent layout. Children resolve in source order, with separate input
namespaces, retained completed results, and authorization checked on retry.
The parent handler is not reconstructed after an input boundary. Resource bodies can return @racket[text-presentation] with strings and embedded
text resources, @racket[json-presentation] with a JSON value, or
@racket[binary-presentation] with bytes and an explicit MIME type. These constructors
produce persistable representations. Text presentation resolves nested children
before concatenation; JSON is labelled @tt{application/json}; binary content uses
the protocol's base64 blob field. Binary content is never implicitly decoded as
text. Arbitrary host string operations are not deferred presentation forms.
@racket[resource-contents] returns an explicit sequence of resource presentations.
Each part retains the declaration's resolved URI and its own presentation MIME
type. Empty and nested sequences are supported. Embedding such a resource preserves
all parts in order: tool content expands into separate embedded-resource items,
and prompt content expands into single-content messages retaining the original
role. Text presentations concatenate embedded text parts without inserting a
separator; binary parts require explicit conversion. JSON presentations and
structured tool values represent a multi-content embedding as an array. Single
content embeddings retain their existing object representation. Use
@racket[binary-presentation] for persistable binary parts.
@racket[resource-content] instead wraps an explicit JSON resource content object
with a string @tt{uri}, exactly one string @tt{text} or @tt{blob}, and an optional
string @tt{mimeType}. It preserves that URI and metadata, allowing a read to return
multiple related resources with distinct identities.

Durable rendering stores all completed child content. Its record version is now
@tt{render/3}; older records fail with a version diagnostic because they may have
already discarded content. Application workflow versions remain independently
checked. SDK rendering markers carry a private Racket property; identical JSON
objects remain ordinary data. SQLite stores marker provenance in separate columns
for state, arguments, and journal events. Public JSON decoding cannot supply this
provenance. No application JSON key by itself activates an embedded resource
read or content-group expansion. SDK storage
preserves it across process restarts; an ordinary JSON round trip intentionally
does not. Existing tables gain nullable sidecar columns. Legacy rows without
marker-shaped data remain readable; ambiguous legacy rows fail with an explicit
recovery diagnostic rather than being interpreted as resource reads.

Rendering after a completed workflow uses a stable key bound to that workflow
instance, so retrying its continuation retains completed child results.

A resource can attach a named renderer with @racket[#:render].
@racket[make-text-renderer], @racket[make-json-renderer], and
@racket[make-binary-renderer] take a name, version, and unary procedure. The
resource advertises the renderer's MIME type; a conflicting explicit resource
MIME type fails construction. Text renderers return a string or a list of text
and embedded-resource parts. Binary renderers return bytes; JSON renderers return
JSON values. @racket[make-resource-renderer] accepts an explicit MIME type and a
procedure returning a matching presentation.

Ordinary resource handlers may return host values, such as generated shape
instances, which the renderer converts before persistence. Workflow completion
values still require a persistable representation. Renderer expressions run once
at declaration instantiation; rendering runs on demand inside the persistent
embedding context. Completed parent rendering survives child suspension without
reconstructing its handler or renderer. Renderer identity, version, and MIME type
contribute to continuation compatibility; changing renderer code requires updating
its version until complete executable build fingerprints are available.

@racket[role] expands several content items into the required sequence of
single-content prompt messages. Prompt arguments remain strings on the wire.
A declared string codec converts them to checked JSON-representable domain values:
@racketblock[
(define integer-text
  (make-string-codec "integer-text" "1" Integer number->string string->number))
(prompt (counting [start Integer #:codec integer-text]
                  [next Integer #:codec integer-text #:default (add1 start)])
  (role "user" (text-content (number->string next))))
]
@racket[make-string-codec] takes its name, version, domain schema, encoder, and
decoder. Decoder results must satisfy both the codec and argument schemas. Missing
optional arguments remain @racket[missing]; defaults are domain expressions and
can reference earlier decoded arguments. Defaults bypass the wire decoder.
Codec expressions run once during descriptor construction. Encoding and decoding
procedures should be pure; resumed requests may decode the echoed strings again.

The ordinary descriptor API uses @racket[prompt-argument], which extends
@racket[argument] with a codec field. @racket[encode-prompt-arguments] produces a
wire argument object from supplied domain values without evaluating defaults.
Codec identity, version, and schema contribute to durable prompt compatibility.
This string-codec API supports JSON domain values; arbitrary host structures use
the separate checkpoint/effect @racket[value-codec] mechanism.

@subsection{JSON and validation budgets}
@racket[read-json] counts consumed UTF-8 bytes for @racket[#:max-bytes], including
multibyte characters, and rejects malformed UTF-8 without substituting replacement
characters. It reads one value and preserves following input. @racket[string->json]
requires the remaining input to contain only JSON's four whitespace characters.

@racket[validate] and @racket[valid?] accept @racket[#:max-steps] (default
1,000,000) in addition to @racket[#:max-depth]. Registry indexing, construction
metaschema evaluation, applicator visits, and property/item traversal share the
budget within a validation call. Exhaustion raises an error; it never produces a
successful or ordinary invalid result. Later independent calls receive a fresh
budget. This bounds counted structural work, not the CPU cost of arbitrary regex
matching or large numerical operations. Registry cycles are rejected explicitly.

@subsection{Schema construction checks}
@racket[check-schema!] validates declarations against the pinned, offline 2020-12
metaschemas and raises @racket[exn:fail:schema] with schema/instance diagnostics for
malformed keyword values. Its @racket[#:max-depth] and @racket[#:max-nodes] keywords
bound the schema value graph; cyclic and non-JSON host values are rejected.
Standard metaschemas cannot be replaced by application registry entries. Explicit
custom dialects use the preloaded registry, and unknown required vocabularies fail.
The installed package includes the pinned @tt{vendor/metaschemas} resources.
No schema validation operation performs network access.

Metaschema format keywords retain annotation semantics. This construction gate
therefore does not establish complete URI-format or ECMA regular-expression
compatibility; those remain separately documented validation limits.

@section{Workflow execution}
A checkpoint evaluates replay-safe computation while retaining its workflow worker
claim, without holding the SQLite transaction. Its validated result and stage
advance commit atomically afterward. Cancellation is checked again inside that
transaction; a cancelled task cannot commit the computed checkpoint or start the
next stage. Transactional application mutations belong in @racket[perform] with a
transactional adapter, not in checkpoint computation.

@racket[#:execution task] requires client Tasks capability before work is queued.
@racket[#:execution task-optional] explicitly selects task execution when that
capability is present and ordinary MRTR workflow execution otherwise. The default
remains @racket[#:execution mrtr]. Both task modes require a workflow descriptor;
unknown execution modes fail construction or language expansion.

Task input updates ignore unrecognized response keys. An update containing only
unknown keys acknowledges without advancing or restarting the worker. Recognized
elicitation responses are validated before the task changes state, so malformed
input does not turn a pending task into a failed task.

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
@racket[if] and @tt{match} blocks may contain persistent stages in tail or
non-tail position. Decisions and match subjects are persisted; branch exits join
the following stages without re-evaluating the decision. @racket[let] blocks
persist initializers from left to right, each in the outer lexical environment,
then introduce their bindings for the block. Initializers must be replay-safe
JSON computations. Inner bindings may shadow outer bindings and do not escape
the block. @racket[begin] groups a sequence of stages. The private compiler retains
source-aware workflow nodes and checks branch/join destinations before emission.
Host expressions cannot hide suspension forms. Persistent stage values must be
JSON encodable and satisfy the stage schema, or use a @racket[value-codec] in
place of that schema. @racket[make-value-codec] takes a name, version, JSON schema,
encoder and decoder. A workflow registers the codecs referenced by its stages;
conflicting registrations fail. Stored values contain codec identity, version
and validated JSON payloads. Decoders must be pure and may run for each resumed
stage. @racket[make-codec-registry] supplies explicit registrations to manual
recovery through @racket[#:codecs]. Codec identity/version/schema changes affect
the workflow fingerprint; ports, closures, and continuations
are not persisted.

A batch uses the form
@racketblock[(await-input ([name Any name-request] [color Any color-request]))]
Request expressions evaluate in declaration order in the outer lexical scope.
Each binder receives its elicitation response, including decline/cancel actions.
Partial answers persist individually. A retry requests only unanswered inputs;
conflicting replacements of accepted answers fail. Each declared response schema
is checked before its value is retained.

Each input round receives its own opaque token. Matching retries retain completed
work, while a conflicting response to a completed input is rejected. Tokens are
bound through storage to the original identity, arguments, operation, executable
version, and expiry. Unknown response fields are ignored. Clients echo tokens
without interpreting them.

An effect stage has the form
@racketblock[(perform [receipt Integer] #:adapter writer #:policy manual input-expression)]
Adapters declare @racket['transactional], @racket['idempotent], or
@racket['manual]. Transactional adapters receive the store connection. Idempotent
adapters receive the saved key across retries. Manual uncertainty requires an
explicit journaled recovery action. A key does not provide exactly-once execution.
Workflow calls hold an instance claim across external effects. Concurrent retries
wait cooperatively and then read the recorded outcome; @racket[recover-workflow!]
rejects changes while execution is active. After uncertainty, competing observed
outcomes cannot both advance the same stage. Claims use the same single-host
file/thread mechanism as Tasks, without keeping an application transaction open
across an external adapter call.
@racket[#:execution task] selects Tasks instead of MRTR. Durable serving requires
an explicit state-file configuration. @racket[make-runtime] scans unexpired working
tasks and starts recovery workers. Awaiting-input and terminal tasks stay unchanged.
Use @racket[#:recover-tasks? #f] to defer startup and @racket[recover-runtime-tasks!]
to scan explicitly; the latter returns worker thread events. A missing executable
is a startup error. Incompatible executable versions fail through the workflow
compatibility check before execution.

@racket[#:restore-principal] maps the stored principal key to a current application
principal. Its default returns the key itself, suitable for string identities.
Applications using verified principals supply their identity/policy lookup. Recovery
checks identity, expiry, and operation authorization after acquiring the worker
claim; no bearer credentials are persisted. A denied recovery fails the task.

SQLite task workers use OS file locks in a sibling @tt{.workers} directory, together
with process-local thread ownership. Keep that directory alongside the database;
do not remove lock files while runtimes are active. Workers use one canonical
state-file path on one host. Process termination releases the OS lock, and retries
retain the workflow's recorded effect policy and key. This is not a distributed
lease protocol. Native lock/restart verification currently covers Linux only.
Clients opt into task status notifications with a @tt{taskIds} string array in
@tt{subscriptions/listen}. The runtime verifies each task's ownership and read
policy before acknowledging the accepted IDs. Committed transitions emit
@tt{notifications/tasks} with the complete detailed task, tagged with the
subscription request ID. Notifications are bounded hints: after reconnecting or
overflow, poll @tt{tasks/get}; there is no notification replay. Terminal no-op
cancellation does not emit a new transition. The exhaustive failure-boundary
matrix remains open.

@section{Transports, policy, and ownership}
@subsection{Stdio}
@defmodule[mcp/stdio]
@racket[make-stdio-client] accepts input/output ports and owns them by default.
Explicit close, EOF, or a decoding/protocol failure resolves all pending handles,
stops the reader, and closes both ports. With @racket[#:close-ports? #f], the
caller retains port ownership; explicit close still stops the reader. Writes use
a separate lock so a blocked peer cannot prevent pending-handle resolution.
@racket[client-request]
returns an event-compatible request handle; @racket[client-call] synchronizes it.
The notification channel is bounded. @racket[request-cancel!] signals cancellation.
Servers validate the JSON-RPC request envelope before scheduling handlers or
acting on stdio cancellation. IDs must be strings or integers; invalid IDs are
omitted from error responses. Non-object messages (including JSON false), wrong
versions, result/error members on requests, and non-object parameters are
rejected. Malformed cancellation parameters on stdio are ignored without sending
a notification response or cancelling an operation.

Stdio has one reader, concurrent bounded workers, and a serialized writer;
handler stdout is routed to the error port. EOF signals request cancellation and
allows one shared 200 ms grace period before shutting down request custodians.
Durable task workers remain owned by the runtime.

Supply a string or integer @tt{progressToken} in request @tt{_meta} to receive
progress notifications through the handle's notification channel. Tokens must be
unique among active requests; completion releases them for reuse. Cancelling an
already completed handle is a no-op. Configure per-handle buffering with
@racket[#:notification-limit] (default 64, a positive integer). Overflow completes
only that handle with @racket[exn:fail:notification-overflow], whose request ID
identifies the affected operation, and queues remote cancellation. Other requests
continue. Re-listen and refresh cached data after a subscription overflow; queued
notifications from the failed handle do not establish a current snapshot.

For requests whose writes started, cancelled and overflowed progress tokens remain reserved until a late response
establishes remote termination, so late progress cannot reach a new request.
Ordinary cancellation need not receive a response; such tokens can remain
reserved until the connection closes. Requests and cancellation traffic share one serialized writer and a bounded
outbound queue. A full queue rejects a new request before writing; failure to
queue necessary cancellation fails the connection explicitly. Closing the client also
stops this worker.
@racket[request-cancel!] resolves an active handle with
@racket[exn:fail:request-cancelled], carrying its @racket[request-id], and queues
stdio cancellation without waiting for output or a server acknowledgement.
A late response cannot replace that local outcome. Completed handles are unchanged.
Servers do not acknowledge cancellation of ordinary requests with a cancellation
notification. Clients accept server cancellation notifications only for a matching
subscription; dedicated subscription completion results remain supported.
HTTP local cancellation uses the same exception type and closes its request.

Stdio request handles are returned after bounded queue insertion, without waiting
for the peer to read output. @racket[make-stdio-client] accepts
@racket[#:outbound-limit] (default 64) and @racket[#:timeout] (default 30 seconds).
@racket[client-request] and @racket[client-call] accept a per-call timeout override.
Timeouts are positive finite seconds or @racket[#f] to disable them. Subscriptions
omit the default total deadline; an explicit per-call deadline still applies.
The monotonic deadline covers queueing, writing, and waiting for a response;
progress does not extend it. A timeout returns @racket[exn:fail:request-timeout]
from the handle (or raises it in a synchronous call), with request ID and seconds.

A request cancelled or timed out before writing is discarded from the queue, and
its token is released. Once writing starts, the client queues cancellation and
retains its progress token as described above. It never writes an expired queued
mutation later, and never replays an uncertain mutation. Writer failure closes the
connection and resolves outstanding handles. Local serialization/argument errors
can still be raised while constructing a request.

@racket[make-stdio-client] accepts @racket[#:request-limit] and
@racket[#:progress-token-limit], each defaulting to 1,024 positive-integer entries.
The first bounds active requests; the second bounds active and reserved progress
tokens together. Reaching a limit rejects the new request before writing it.
When cancelled requests never receive a late response, a fresh connection is
required to discard their reservations. The SDK does not reconnect or replay
operations automatically. Requests without a progress token can continue while
only the token limit is exhausted.

@subsection{Subscriptions}
@defmodule[mcp/subscription]
Subscription acknowledgement is sent before that subscription's queued changes,
without holding the shared hub lock during I/O. A blocked acknowledgement cannot
stall registration or publication for other connections. Changes received during
acknowledgement remain bounded by the hub queue capacity; overflow produces the
subscription error after acknowledgement, without draining stale queued events.
Every hub access removes listeners whose threads were forcibly terminated.

@subsection{List pagination}
Tools, resources, resource templates, and prompts use opaque continuation cursors.
@racket[make-runtime] accepts @racket[#:page-size] (default 100),
@racket[#:cursor-ttl] in seconds (default 60), @racket[#:cursor-limit] (default 1024
retained continuation tokens), @racket[#:cursor-bytes] (default 16 MiB of encoded
snapshot/binding data), and @racket[#:cursor-clock] for deterministic scenarios.
All numeric settings are positive integers.

The first page freezes listing metadata for subsequent pages. Repeating a cursor
returns the same page and next cursor. Cursors bind the method, principal authority,
capabilities, and non-cursor request parameters. Every request still passes through
authorization. Expired, evicted, foreign, or mismatched cursors raise invalid params;
restart the listing without a cursor. Retention evicts whole snapshots. A listing
larger than the configured snapshot capacity raises an explicit server error.
Cursors are runtime-local and do not survive a restart. Pages currently carry
zero TTL and private scope. Low-level SDK calls return each page directly.

Progress uses the caller's string or integer @tt{progressToken}, including zero.
Clients reject reuse of a token across active requests. Tokens become available
again on remote terminal completion; stdio reserves cancelled/overflowed tokens until a late response
confirms termination to prevent late traffic from reaching a new request.
The HTTP client snapshots request parameters before worker startup.

@racket[progress!] from @racketmodname[mcp/subscription] requires an active
request and its original token. Progress and optional totals must be finite
numbers; progress must strictly increase. Optional messages must be strings.
Nested dispatch shares progress ordering for the enclosing request, concurrent
emission is serialized, and emission after completion or cancellation fails.
Clients reject malformed or non-increasing progress for an active request; HTTP
also rejects unrelated progress on the request's stream. These checks do not
require a known total or impose an additional nonnegative-value restriction.

Both clients check incoming JSON-RPC envelopes, object results and metadata,
integer error codes, and string error messages. Unknown result discriminators
fail validation. A @tt{task} result requires the Tasks capability advertised on
that request; capabilities are snapshotted when the request is created. An
absent @tt{resultType} retains the core specification's @tt{complete}
interpretation. These envelope checks do not replace method-specific payload
validation. HTTP JSON and SSE responses must match the request ID when present.
An error without an ID can be returned directly on the request-scoped HTTP
connection. On stdio it cannot be correlated, so the client fails the connection
and resolves outstanding requests with a local exception. Unexpected server
requests and malformed notifications also fail validation.

@subsection{HTTP}
@defmodule[mcp/http]
@racket[make-http-client] and @racket[http-client-request] provide HTTP equivalents.
List tools before calling header-annotated tools, or preload schemas using
@racket[#:schemas]. Invalid header annotations are excluded from HTTP listings.
No standalone GET stream, session ID, or stream resumption is implemented.
SSE responses serialize notifications and completion through a bounded 64-event
queue. @racket[serve-http] and @racket[make-http-handler] accept
@racket[#:keepalive-seconds] (default 15) and @racket[#:max-response-bytes]
(default 1,048,576). Idle streams emit comments and advertise
@tt{X-Accel-Buffering: no}. Failed output signals cancellation, allows 200 ms for
cooperative termination, and shuts down the request custodian. Durable task
workers remain owned by the runtime.

@racket[make-http-client] accepts @racket[#:header-timeout] and
@racket[#:timeout], each defaulting to 30 seconds. The header deadline includes
connection establishment, TLS, request writing, and response headers. The total
deadline includes body reading and SSE processing. Both start when the request is
created, use monotonic time, and accept a positive finite real or @racket[#f]
to disable the limit. @racket[http-client-request] and @racket[http-client-call]
accept per-call overrides. Subscriptions omit the default total deadline; an
explicit per-call @racket[#:timeout] still limits them. Header limits continue to
apply to subscriptions. Keep-alives do not extend an explicit total deadline.
Timeouts produce @racket[exn:fail:http:timeout], whose @racket[phase] is
@racket['headers] or @racket['request] and whose @racket[seconds] records the limit.
The asynchronous handle returns the exception; the synchronous call raises it.
A deadline closes the request's ports and workers without retrying the operation.
Completion, cancellation, and timeout select one terminal outcome; only successful
completion can publish discovered schemas. Cancelling a completed handle leaves
its result unchanged.

@racket[make-http-client] also accepts @racket[#:max-response-bytes]. It bounds
JSON bodies and SSE event accumulation before JSON decoding, handles CR/LF/CRLF
framing and comments, and rejects unrelated response IDs or server requests on
the stream. Completion and cancellation close the request custodian, including
HTTP framing copy workers. The native HTTP/1.1 reader copies bodies in 8 KiB
blocks through a 64 KiB pipe, without allocating advertised chunk or body lengths.
@racket[#:max-header-bytes] on @racket[make-http-client] bounds aggregate response
headers (default 65,536 bytes); chunk framing lines are limited to 8,192 bytes and
trailers use the header budget. Conflicting lengths, ambiguous transfer framing,
and truncated bodies fail the request. HTTPS verifies certificates and hostnames.
The client requests identity content encoding and rejects compressed responses;
it does not follow redirects or replay POSTs automatically. Full disconnect and
subscription acceptance coverage remains open.
@subsection{Authorization}
@defmodule[mcp/authorization]
The server accepts an application token-verification adapter returning a
@racket[verified-principal]. The SDK checks issuer, audience, expiry, and scopes
through explicit APIs. @racket[make-runtime] accepts @racket[#:required-scopes], a
callback from method and parameters to OAuth scope-token strings. This policy is
combined with @racket[#:authorize] throughout local dispatch, embedded reads,
resource notification checks, and resumed work. Scope callbacks should be pure:
HTTP also checks them before starting a response stream.

Pass @racket[#:resource-metadata] to @racket[make-http-handler] or
@racket[serve-http] using a document from @racket[protected-resource-metadata].
An explicit @racket[#:authenticate] adapter is required in this configuration.
The metadata document's issuers, resource audience, and principal expiry are
checked independently of the adapter. @racket[#:resource-metadata-url] optionally
overrides the advertised URL; otherwise @racket[protected-resource-metadata-url]
derives the path-specific well-known URL. The handler serves that path with public
GET and CORS access, and includes its URL in 401 challenges. Required-scope failure
returns 403 with @tt{insufficient_scope} and the required scopes before SSE starts.
Configure the external HTTPS resource identity explicitly when serving behind a
TLS-terminating proxy. Scope strings are validated before inclusion in headers.

@racket[parse-authenticate] parses a list of @tt{WWW-Authenticate} field values
into @racket[authentication-challenge] values containing the lowercase scheme,
a parameter hash with lowercase names, and an optional token68 value. It handles
combined fields, multiple schemes, quoted commas/escapes, and token parameters.
Duplicate names, malformed quoting, and invalid syntax are rejected. The default
aggregate byte limit is 64 KiB, configurable with @racket[#:max-bytes]; each
challenge permits at most 64 parameters.

HTTP 401 and 403 complete the low-level request handle with
@racket[exn:fail:http:authorization]. Its fields retain the numeric status, raw
response headers, bounded body bytes, parsed challenges, and the failed request's
resource and token. The retained token is credential data; the exception message
does not include it. The synchronous
@racket[http-client-call] raises that exception. Empty and non-JSON challenge
bodies are valid transport outcomes. These APIs do not perform authorization,
open a browser, or retry the operation automatically.

@racket[client-id-metadata-document] builds a public client document from its
HTTPS URL, display name, and redirect URI list, with optional @racket[#:extra]
metadata. @racket[check-client-id-metadata!] validates a document against its
exact hosting URL. Client IDs require a path and reject credentials, fragments,
and literal or encoded dot segments. Shared-secret fields are forbidden. This
implementation emits and accepts the public @tt{none} token authentication method;
private-key JWT client authentication is not implemented. Applications host the
returned JSON at the supplied URL.

@racket[select-oauth-registration] takes authorization-server metadata, resource,
redirect URI, and requested scopes. It first checks @racket[#:pre-registered], a
hash from exact issuer strings to @racket[oauth-registration] values. The selected
entry must match that issuer and redirect; its resource and scopes are replaced
with the current request's values. If no matching entry exists, an explicitly
advertised @tt{client_id_metadata_document_supported: true} permits the supplied
@racket[#:client-metadata] and @racket[#:client-metadata-url]. Otherwise
@racket[#:request-registration], if supplied, receives issuer and redirect and
returns a checked registration. Missing configuration raises a diagnostic.
Selection does not perform dynamic registration or publish the metadata document.

@racket[discover-authorization-for-resource] takes the exact resource identifier
and a metadata-fetch callback. It tries path-specific then root protected-resource
metadata, unless @racket[#:metadata-url] supplies the URL advertised in a challenge.
It requires exact resource identity. @racket[#:select-issuer] chooses from the
advertised issuer list (default: first); an unadvertised selection is rejected.
Authorization metadata follows OAuth path insertion, OIDC path insertion, and,
for a path-bearing issuer, OIDC path appending. @racket[authorization-metadata-urls]
exposes that ordered list. Issuer equality is exact, and the authorization server
must advertise the code response type and HTTPS authorization/token endpoints.
@racket[validate-authorization-metadata!] checks required and known optional field
types, URLs, grant support, and JWT client-authentication algorithm declarations.
With @racket[#:oidc? #t], it also requires the HTTPS key-set URL, valid subject types,
and RS256 among ID-token signing algorithms. Discovery applies these extra checks
to documents returned from OIDC fallback endpoints. Invalid documents stop fallback.
These checks validate metadata; they do not fetch keys or verify ID tokens.

The fetch callback returns a decoded metadata object, or @racket[#f] when that
endpoint has no document. Only @racket[#f] permits fallback. Exceptions and invalid
or mismatched documents stop discovery. Fetch adapters must enforce their own
network and response limits. @racket[discover-authorization] retains the explicit
metadata-URL entry point; supply @racket[#:resource] to bind the returned document
to the expected resource. Resource queries remain part of identity while discovery
URLs omit them. Issuer identifiers cannot contain queries.

@subsection{Explicit authorization runner}
@defmodule[mcp/oauth]
@racket[make-oauth-authorizer] configures a resource, redirect URI, and
@racket[#:browse] callback. The browser callback receives the PKCE authorization
URL and returns a hash containing the callback's state, issuer, and code (or
@racket[#f] for cancellation). Native fetch/exchange adapters are defaults;
@racket[#:fetch] and @racket[#:exchange] can replace them. Registration and issuer
selection use the options described above.

@racket[authorize-resource!] performs discovery and obtains an
@racket[oauth-credential]. Supply parsed @racket[#:challenges], optional
@racket[#:scopes], and the actual @racket[#:rejected-token] when responding to a
failed authenticated request. Challenge scopes take precedence; otherwise explicit
scopes or protected-resource defaults apply. Multiple Bearer challenges require
the caller to select one. The runner does not issue or retry an MCP operation or
automatically install a token on a transport.

Credentials are keyed by issuer, client ID, and resource. @racket[#:load] receives
those three keys and returns a credential or @racket[#f]; @racket[#:save] receives
the keys and credential. Callbacks must honor that complete key. Defaults provide
in-memory reuse without durable persistence. Calls through one authorizer are
serialized, including refresh and browser interaction. Callbacks must not reenter
that same authorizer; cross-process coordination is the application's responsibility.

An unexpired credential covering the required scopes is reused. An expired or
explicitly rejected credential can refresh if its previous grant covers those
scopes; additional scopes and insufficient-scope challenges use the browser.
Refresh responses omitting scope retain the previous grant. Empty requested scopes
omit the authorization URL's scope parameter. Malformed token responses are rejected.

An exchange failure is surfaced and further exchanges require explicit
@racket[#:reauthorize? #t], which starts a fresh browser flow. A successful exchange
whose save callback fails remains in memory; the next call retries persistence
before proceeding, without repeating the consumed code or refresh token. That
in-memory recovery does not survive process loss: applications must resolve an
uncertain durable credential write before restoring stale credentials after restart.

@subsection{Authorizing an HTTP client}
@defmodule[mcp/oauth-http-client]
@racket[authorize-http-client!] takes an HTTP client and configured authorizer,
optionally the @racket[#:failure] returned by an HTTP request. It obtains and
installs a credential, then returns that credential. It never retries the MCP
operation. The caller decides whether and when to issue another request.

The client URL, authorizer resource, and failure resource must agree exactly.
HTTP requests snapshot their URL and token before starting workers, and failures
retain those values. The helper passes the actual rejected token to the authorizer,
so delayed challenges do not invalidate a newer cached credential. Before
installation it checks for URL changes or a different token installed by an
application callback. @racket[#:scopes] and @racket[#:reauthorize?] pass through to
the explicit runner. Full end-to-end provider interoperability remains unverified.

@subsection{Native OAuth HTTP}
@defmodule[mcp/oauth-http]
@racket[make-oauth-http-adapters] returns two synchronous callbacks: metadata fetch
and token exchange, usable with the discovery and PKCE APIs. Fetch uses GET;
exchange accepts a hash of string form values and uses POST with form encoding.
Only metadata GET 404/405 returns @racket[#f]. Other non-200 statuses raise
@racket[exn:fail:oauth-http], retaining status, headers, and body bytes. Successful
responses must contain an @tt{application/json} object. No credentials are attached
to metadata requests, and redirects and retries are not automatic.

Options are @racket[#:timeout] (30 seconds), @racket[#:max-response-bytes] (1 MiB),
and @racket[#:max-header-bytes] (64 KiB). A request custodian cleans up sockets and
copy workers on completion, errors, timeouts, and caller exception/break unwinding.
HTTPS verifies certificates and hostnames. @racket[#:allow-loopback-http? #t]
explicitly permits literal loopback HTTP for local development fixtures; it does
not relax the discovery API's HTTPS identifier checks.

OAuth functions create PKCE requests and validate state and issuer during exchange.
Applications can use the native fetch/exchange callbacks or supply their own.
Browser interaction and credential persistence remain application callbacks;
complete registration and credential-flow orchestration is still in progress. Hosted authorization services
and dynamic client registration are outside the package scope.

@subsection{Explicit interaction runner}
@tt{mcp/interaction} exports @racket[run-interaction]. Its request callback accepts
method and parameter values and must issue a fresh JSON-RPC ID on every call.
Low-level client calls return protocol outcomes directly; only this explicit runner
performs follow-up requests. Supply @racket[#:elicit] and @racket[#:navigate]
callbacks returning input responses. Decline and cancellation responses are retained.
Exceptions and protocol errors stop the interaction without replaying the request.

The runner echoes opaque request state exactly, omits it when absent, and replaces
previous-round input responses. It supports input-only and state-only results;
malformed input-required results fail before retry. Missing @tt{resultType} means
@tt{complete} under the protocol's client fallback rule. Tasks are polled and updated
through the same callback, which must carry the application's capabilities and
credentials. @racket[#:wait] supplies polling waits; @racket[#:max-rounds] is a
positive integer, default 100, bounding loop rounds rather than individual messages.

@section{Composition, extensions, and inspection}
@racket[mount] composes descriptors and registers the result in a language module.
@racket[view] supports selection, renaming, namespaces, and simple URI remapping.
Reference identity survives remapping. @racket[#:require-scopes] adds OAuth scope
requirements to every retained tool, resource, and prompt. Nested views accumulate
requirements; selection, renaming, URI mapping, and mounting preserve them. A
completion inherits its target's requirements. These checks do not infer authority
from tool annotations.

The data API accepts @racket[make-interface] with @racket[#:requirements], a hash
from an included declaration descriptor to a list of scope tokens.
@racket[interface-requirements] returns the copied immutable mapping. Requirements
for absent declarations are rejected. Runtime @racket[#:required-scopes] policy
adds to these requirements. An empty list does not remove inherited policy.

Scope checks precede execution and cache access, and apply again to embedded
resource reads, workflow retries, task polling/update/cancellation, and task
notification delivery. HTTP uses the combined requirements in insufficient-scope
challenges. A scoped operation requires a verified principal; applications supply
one explicitly for local/stdio dispatch. Discovery and declaration listing remain
visible unless the runtime's own policy restricts those methods. Scope requirements
are execution policy and do not automatically filter lists. Trusted Racket authors
can construct another interface; this API is not a sandbox for application code.

@racket[view] accepts @racket[#:adapters], a hash from adapter symbols to
@racket[versioned-effect-adapter] values. Each value contains its effect policy,
three-argument invocation procedure (input, idempotency key, transaction connection),
and a nonempty application-defined version string. The transaction connection is
@racket[#f] for external policies. The existing @racket[effect-adapter] constructor
remains available for runtime bindings; view replacements require explicit versions.

Replacements override runtime adapter bindings only for retained declarations in
that view. Nested views preserve bindings unless explicitly replaced; sibling
mounts are independent. The data API's @racket[#:adapter-bindings] maps included
declarations to these adapter hashes, available through
@racket[interface-adapter-bindings]. All maps are copied at construction.

Versions of adapters referenced by effect stages contribute to persisted workflow
compatibility. Changing a referenced adapter version or policy rejects an existing
execution before its next stage; unchanged explicit versions permit reconstruction
of procedures after restart. Versions are an application compatibility promise,
not a hash or proof of procedure equivalence. Imported helper fingerprint coverage
remains incomplete. New tasks additionally retain the published tool name so sibling
mounts resolve their own bindings during updates and startup recovery. Failed tasks
remain terminal when their workflow requires recovery.

These replacements are named effect bindings, not interception of arbitrary Racket
I/O. Enforced effect restrictions and upstream MRTR/Tasks bridging remain incomplete.

@subsection{Pinned upstream interfaces}
@tt{mcp/upstream} exports @racket[capture-snapshot],
@racket[make-upstream-interface], and @racket[check-upstream-compatibility!].
A request callback accepts a method string and parameter object and returns a
protocol response or result. It owns connection configuration, request metadata,
and upstream credentials. Snapshot capture traverses discovery and every page of
available tools, resources, templates, and prompts.

@racket[make-upstream-interface] copies the JSON snapshot and constructs local
descriptors without calling the peer. Before the first invocation it compares
published declarations, supported versions, and capabilities with a fresh snapshot;
a change requires explicit refresh and review. This is a conservative equality
check, not a proof of schema compatibility, and it is not continuous monitoring.

Tools, resources, prompts, and advertised completions forward to the peer.
Prompt arguments stay strings, absent optional arguments are omitted, and complete
prompt result objects retain their description. Ordinary prompt handlers can also
return a complete result object with a @tt{messages} list instead of a messages
list alone. Completion handlers accept either a list of strings or a completion
object with at most 100 values and optional @tt{total} and @tt{hasMore}; the latter
preserves a peer's partial-result metadata.

Simple template arguments are inferred as required strings. Complex or ambiguous
templates require @racket[#:templates], a hash from the original template URI to
@racket[upstream-template-adapter] values containing argument descriptors and an
explicit inverse matcher. A matcher returns a bound-argument hash or @racket[#f].

Mounted views remap known resource links and embedded-resource URIs, including
multi-content reads and prompt messages. Removed known resources fail resolution.
Unrecognized external URIs and arbitrary structured application JSON remain data.
Completion forwarding retains the peer's original prompt name or template URI
while local lookup uses the transformed declaration. Upstream MRTR and Tasks
outcomes still fail explicitly: persistent handle translation is unfinished.

@racket[define-mcp-extension] accepts @racket[#:declaration] or @racket[#:workflow]
before a transformer expression. Omitting the kind means @racket[#:declaration].
The transformer runs at phase 1, accepts syntax, and returns core syntax. Require
its dependencies with @racket[for-syntax] and export/import the extension identifier
normally; renamed imports preserve its extension class.

Declaration extensions lower through a private @tt{syntax-spec-v3} extension class
and then ordinary module expansion. They can emit helper definitions and core MCP
declarations. The separately compiled @tt{collection} example demonstrates this
path. Servers generated by extensions get the normal executable entry point;
executing a fragment without a server produces the serving command's diagnostic.

Workflow extensions use a distinct private extension class. The workflow compiler
expands each stage head before parsing and checking the resulting core stage IR.
Transformers may return @racket[begin], checkpoints, input/effect stages, or the
supported control forms. Host expressions retain their lexical environment and
are not expanded by this extension pass. A workflow extension used in a host
expression, including inside a checkpoint expression, is rejected. Generated
binders and core clauses still pass duplicate, scope, and graph checks. Source
syntax from the transformer is retained for diagnostics. The separate
@tt{approval.rkt} example defines a reusable elicitation stage.

Normalized emitted stages contribute to workflow fingerprints, so changing an
extension's generated code changes continuation compatibility even when its caller
is unchanged. This compiler revision uses @tt{mcp-workflow/3}; older saved programs
require compatible code. Complete fingerprints for imported runtime helpers remain open.

The compiler uses distinct @tt{syntax-spec-v3} classes for schema, operation,
resource, effect, and workflow-value bindings. Public @racket[schema],
@racket[shape], @racket[tool], @racket[prompt], @racket[resource], and
@racket[workflow] declarations establish those bindings; extensions emit these
forms rather than depending on private class constructors. Ordinary imports,
renaming, and @racket[dynamic-require] preserve descriptor values. Module schema
and operation bindings are immutable identifiers. Ordinary @racket[define] values
remain ordinary Racket bindings and can supply dynamically constructed schemas.
Known operation/resource identifiers used directly as schemas fail expansion;
computed expressions retain runtime validation.

Resource bindings keep the checked reference arity facade. Effect names occupy a
separate binding space, so @racket[perform]'s adapter name does not capture a
same-named host variable. Conflicting policies for one adapter fail in both the
compiler and dynamic workflow constructor. Workflow values retain stage-local
Racket mutation semantics. At the REPL, declarations use ordinary definitions;
the checked module binding metadata is unavailable there. Whole-interface
reference analysis remains unfinished.
Compiler modules and their IR are private and are not extension APIs.

The manifest submodule can be instantiated without the parent application.
Its @tt{manifest-version} export is 2. Each declaration records its kind, name,
source location, argument requirements, and explicit metadata clauses. Schema
primitives and same-module schema aliases/shapes resolve without evaluating
application expressions. Known values use @tt{known?} and @tt{value}; unresolved
expressions use @tt{known?} false and a printable @tt{expression}. Defaults are
recorded, never executed by inspection. Imported and computed schemas may remain
dynamic. Tool declarations include an input schema when argument schemas resolve.

Tool, prompt, and resource workflows additionally record normalized stages,
source locations, schemas, adapter names or branch targets, and effect policies.
Workflow storage is a runtime requirement; adapters are required only when an
effect stage exists. This is declaration information, not a complete runtime
capability advertisement. Static resource URI collisions and schema-alias cycles
fail expansion. Compiling a module still executes trusted transformers.
@tt{inspect}, @tt{diagram}, @tt{docs}, @tt{check}, @tt{scenario}, @tt{snapshot}, and
@tt{diff} are available through @tt{raco mcp} after package registration, or
@tt{racket -l mcp/cli --}. Current documentation and compatibility output is basic;
it does not establish arbitrary schema subsumption or handler equivalence.

@section[#:tag "freshness"]{Committed changes and resource dependencies}
A resource can declare keys with @racket[#:depends-on]; the expression runs with
validated URI arguments when matching an eligible resource subscription. Keys are
a list of JSON values. Mounts and URI views retain the dependency callback.

@racketblock[
(resource (document [id String]) #:uri "document:///{id}"
  #:depends-on (list id)
  (read-document id))
(tool (save-document [id String] [body String])
  #:changes [outcome (list id)]
  (write-document-and-commit! id body)
  (committed-result (text-result "Saved") '()))
]
The change clause binds an explicit successful outcome name alongside validated
arguments. It runs only after @racket[committed-result] acknowledges a commit;
ordinary successful results and execution errors do not imply a commit. The
wrapper's own key list is combined with declared keys. Notifications follow the
commit acknowledgement even when later rendering requires input or fails.
Application code must issue that acknowledgement only after its mutation commits.

The data API accepts @racket[#:depends-on] on @racket[make-resource] as a procedure
of bound arguments, and @racket[#:changes] on @racket[make-tool] as a procedure of
bound arguments and committed result. @racket[runtime-report-change!] accepts a
runtime, principal, and keys for external committed changes. It invalidates that
principal's entries in @racket[runtime-cache] before publishing matching resource
updates, rechecking the subscriber's read authorization and principal expiry.

With storage, acknowledged tool changes enter the outbox before publication.
Applications sharing SQLite can call @racket[record-committed-change!] inside
@racket[store-transaction] alongside their mutation, then call
@racket[runtime-drain-changes!] after commit. Outbox callbacks tolerate duplicate
publication after interruption. A separately committed external mutation still
needs adapter reconciliation if the process exits before recording its change.

Resources opt into caching with @racket[#:ttl-ms] (default zero), available on both
@racket[resource] and @racket[make-resource]. Successful ordinary reads are cached;
workflow resources and requests carrying durable continuation or invocation state
bypass caching and return zero TTL. Input-required results are never cached.
Cache hits return their remaining TTL. A parent inherits the earliest expiry of
its embedded resources and the verified principal's expiry.

Entries include the runtime namespace, principal owner, effective authorization
context, client capabilities, validated arguments, and dependency keys. Verified
principals use all their claims by default. @racket[make-runtime]'s
@racket[#:cache-context] callback can supply a stable immutable application policy
key; it must change when effective authority changes independently of the principal.
Opaque or mutable application principals should use that callback. Cache hits
recheck read authorization for the resource and all transitively embedded URIs.
Changes invalidate all cached authority contexts for their owner, including parent
entries dependent on changed children. Cross-principal change policies remain open.

@racket[make-resource-cache] bounds entries with @racket[#:limit] (default 1024).
Computation occurs outside its lock; concurrent loads can compute twice, but
invalidation prevents an in-flight old value from being inserted afterward and
reduces that returned resource result's TTL to zero.

@subsection{Durable workflow changes}
@racket[workflow] accepts @racket[#:changes [outcome expression]] after its key
clause. The expression sees original bound arguments and the completed result.
Its key list enters the outbox in the same transaction as the terminal result;
continuation retries retrieve that result without reevaluating the clause.
Completion errors do not evaluate it. Like checkpoint computation, change
expressions must tolerate rollback and retry before the transaction commits.

An effect adapter can return @racket[committed-result] containing its ordinary
stage value and immediate dependency keys. A transactional adapter's mutation,
validated stage result, and outbox entry share SQLite's transaction. Idempotent
and manual adapters record acknowledged keys with their saved result; uncertain
external mutations still require reconciliation or explicit recovery.
@racket[recover-workflow!] accepts an acknowledged result for outcome repair.
The journal links each recorded change batch to its stage and outbox handle.

Runtime workflow and task workers attempt publication after committed stages,
including before a later input boundary. Publication failure retains the outbox
entry and reports a diagnostic without changing an already committed effect or
terminal outcome. Direct @racket[run-workflow] callers can drain the outbox
explicitly. Workflow execution owns its transaction boundaries and rejects being
wrapped in an existing transaction on the same store.

@section{Verification boundary}
The pinned core JSON Schema suite has 1,301 cases. Passing it does not establish
optional format assertion or complete ECMAScript pattern compatibility.
Independent MCP evidence and exclusions are recorded under @tt{test-artifacts}
and in @tt{IMPLEMENTATION.md}. Run @tt{sh scripts/check-interop.sh} to reproduce
pinned Go SDK discovery/tool, pagination, and bidirectional progress/cancellation
probes. They check actual remote handler cleanup and continued use of the same
connection. They do not establish the full transport race or conformance matrix.
Native macOS, Windows, and additional Racket releases have not been verified in
this Linux workspace.

@section{Checked completion references}

@racket[(completion (target argument) handler)] constructs and returns a completion
 descriptor under ordinary @racket[(require mcp)]. In @tt{#lang mcp} it additionally
 registers that descriptor with the interface. The handler expression evaluates
 once during descriptor construction; the handler itself accepts a prefix and
 context and runs only when completion is requested.

For locally declared targets, expansion rejects targets other than prompts or
 resources, unknown argument names, and duplicate target/argument routes. The
 manifest records the target, argument, and declaration source without evaluating
 handler expressions. Imported or host-supplied target information that the local
 compiler cannot establish is marked dynamic. Interface construction checks target
 membership, argument existence, and duplicate routes for every completion,
 including descriptors supplied through the ordinary data API. Views remap retained
 completion targets and remove completions belonging to excluded targets.

These checks do not infer resource references hidden in arbitrary Racket handlers;
 complete cross-module interface-reference analysis remains a separate requirement.

@section{Schema construction boundaries}

Literal JSON schemas are checked during expansion wherever declarations accept
 schemas: named schemas, shape fields, tool arguments and output contracts,
 resource and prompt arguments, and workflow checkpoint, input, grouped input,
 and effect representations. Errors retain the offending schema's source syntax.
 Boolean schemas remain valid. Quoted data is inspected only when @racket[quote]
 refers to Racket's quote form; user macros and computed expressions are not
 evaluated to discover their values.

The tool, resource, and prompt constructors share argument checks: unique symbolic
 names, valid schemas, boolean optional flags, and defaults accepting the previously
 bound arguments. An argument with a default must be optional. Schema expressions
 evaluate once in declaration order; defaults remain deferred until an absent
 argument is bound. Interface construction also validates argument and tool schemas
 supplied through raw public descriptors, and runtime construction performs those
 checks before recovery starts.
