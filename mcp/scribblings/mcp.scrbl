#lang scribble/manual
@(require (for-label racket/base (only-in racket/string non-empty-string?) (only-in mcp/build current-build-identity call-with-build-identity) racket/async-channel racket/contract/base (only-in mcp tool schema shape resource task-boundary text-result structured-result error-result load-interface interface-descriptor? interface-requires-state?)
                     (only-in mcp/cli serve-interface-command)
                     (only-in mcp/interaction run-interaction)
                     (only-in mcp/stdio make-stdio-client client-close! request-handle?
                              request-handle-id request-handle-notifications request-cancel!)
                     (only-in mcp/runtime runtime-observe-upstream-task!)
                     (only-in mcp/upstream make-upstream-bridge upstream-bridge? bridge-upstream-request recover-upstream-request! recover-upstream-task! retry-upstream-task!)))
@title{MCP for Racket: Development API}
@author{Racket MCP contributors}

This package targets MCP 2026-07-28 and Racket 9.2. It is an implementation in
progress, not a completed conformant release. The repository implementation
ledger is the authority for missing behavior and executed verification.

@section{Ordinary SDK values and constructors}

@tt{mcp} exports the ordinary descriptor API alongside the declaration forms.
The focused modules are @tt{mcp/descriptor}, @tt{mcp/schema}, @tt{mcp/workflow},
@tt{mcp/runtime}, @tt{mcp/stdio}, @tt{mcp/http}, and @tt{mcp/interaction}.
The following records have their usual Racket predicates and field accessors
(for example, @tt{tool-descriptor-name}). Descriptor construction does not start
transports, open application storage, or call handlers.

@tabular[#:sep @hspace[1]
 (list
  (list @bold{Value} @bold{Fields / representation})
  (list @tt{server-descriptor} @tt{name version instructions})
  (list @tt{argument} @tt{name schema optional? default})
  (list @tt{prompt-argument} @elem{The @tt{argument} fields plus @tt{codec}.})
  (list @tt{tool-descriptor} @tt{name description arguments input-schema output-schema handler annotations workflow execution raw? changes})
  (list @tt{resource-descriptor} @tt{name uri description mime-type handler arguments matcher identity workflow renderer depends-on ttl-ms})
  (list @tt{prompt-descriptor} @tt{name description arguments handler workflow})
  (list @tt{interface-descriptor} @tt{server tools resources prompts completions})
  (list @tt{resource-ref} @tt{declaration arguments})
  (list @tt{request-context} @tt{principal capabilities request-id cancelled? notify})
  (list @tt{workflow-descriptor} @tt{name version fingerprint stages key changes})
  (list @tt{workflow-stage} @tt{id kind schema procedure adapter policy})
  (list @elem{Schema} @elem{A JSON object hash or Boolean schema; @tt{schema} binds one of these values.})
  (list @elem{Result} @elem{A JSON hash produced by explicit content/result constructors.}))]

Use the checked factories for dynamic interfaces. Raw record constructors remain
available, but @tt{make-interface} and @tt{make-runtime} recheck their contracts.
Resource and prompt declaration identities survive views; display names are not
substitutes for those identities. Interface policy and reference maps are obtained
with @tt{interface-requirements}, @tt{interface-adapter-bindings},
@tt{interface-adapter-restrictions}, and @tt{interface-resource-references}; they
are not extra positional fields in the public five-field interface record.

@itemlist[
 @item{@tt{(make-interface #:server server #:tools tools #:resources resources
 #:prompts prompts #:completions completions #:requirements requirements
 #:adapter-bindings adapters #:references references #:adapter-restrictions restrictions)}.
 Every keyword is optional: server defaults to @tt{#f}, declaration collections to
 empty lists, and policy/reference collections to empty hashes. It returns a
 checked interface, resolving declaration identities and rejecting duplicates,
 missing references and ambiguous mappings.}
 @item{@tt{(make-tool name arguments handler)} accepts optional
 @tt{#:description} (empty string), @tt{#:output} (absent), @tt{#:annotations}
 (empty JSON hash), @tt{#:workflow} (@tt{#f}), @tt{#:execution} (@tt{'mrtr}),
 @tt{#:input-schema} (derived from arguments), @tt{#:raw?} (@tt{#f}), and
 @tt{#:changes} (a two-argument callback returning no keys by default).
 The unary handler receives the bound argument map. With @tt{#:raw? #t}, it
 instead receives the validated wire argument object without applying argument
 defaults. Successful structured output is validated against @tt{#:output}.}
 @item{@tt{(make-resource name uri handler)} accepts optional @tt{#:description},
 @tt{#:mime-type}, @tt{#:render}, @tt{#:arguments}, @tt{#:matcher},
 @tt{#:workflow}, @tt{#:depends-on}, and @tt{#:ttl-ms}. Defaults are an empty
 description/argument list, no explicit renderer/workflow, generated URI matcher,
 no dependency keys, and zero TTL. MIME type comes from the renderer or defaults
 to @tt{"text/plain"}. Its handler receives positional bound URI arguments.}
 @item{@tt{(make-prompt name arguments handler)} accepts @tt{#:description}
 (empty string) and @tt{#:workflow} (@tt{#f}). Its unary handler receives a bound
 argument map. Prompt wire values remain strings; @tt{prompt-argument} supplies
 the explicit string codec for a different domain value.}
 @item{@tt{(make-workflow name version fingerprint stages)} accepts @tt{#:key}
 (@tt{#f}) and @tt{#:changes} (a two-argument callback returning no keys).
 It validates the explicit execution-stage program and its codecs. The durable
 execution chapter defines stage kinds, effects and resumption; compiler IR is
 private and is not a substitute for these runtime stage records.}]

Argument names are symbols, schemas are native schema values, and @tt{optional?}
is a Boolean. A @tt{default} is @tt{#f} or a unary procedure receiving the map of
previously bound arguments. It runs only when that optional argument is absent.
The @tt{missing} sentinel, @tt{json-null}, and @tt{#f} remain distinct. Calling a
resource descriptor or @tt{(resource-ref descriptor values)} constructs a checked
reference without I/O; @tt{link} serializes a link and @tt{embed} resolves content
through the current interface and authorization context.

During a handler, @tt{(current-request-context)} is the request's context record.
Its @tt{principal} is the configured local principal or verified HTTP identity;
@tt{capabilities} contains this request's advertised client capabilities;
@tt{request-id} identifies the current request. @tt{cancelled?} is a zero-argument
cooperative cancellation query and @tt{notify} is the active notification sink.
Use protocol helpers such as @tt{progress!} to enforce their notification contracts.
The parameter defaults to @tt{#f} outside dispatch. A context contains live
procedures and must not be persisted as a workflow value.

@tt{(make-runtime interface)} installs storage, adapters, authorization and request
facilities. Optional @tt{#:store}, @tt{#:adapters}, @tt{#:authorize},
@tt{#:required-scopes}, @tt{#:clock}, @tt{#:recover-tasks?} and
@tt{#:restore-principal} configure those facilities; the pagination and freshness
chapters document the cache/cursor settings. @tt{#:store} defaults to @tt{#f};
durable serving requires an explicit store path. @tt{#:recover-tasks?} defaults
to true, so creating a configured runtime may start persisted task recovery.
That is distinct from constructing its descriptors.

@tt{(dispatch runtime method params #:principal principal #:id id #:notify notify)}
returns a protocol result body and raises @tt{exn:fail:mcp} for a protocol error.
Principal defaults to @tt{'local}, ID to @tt{#f}, and notification sink to
@tt{void}. Supply per-request metadata with @tt{request-meta}.
@tt{(dispatch-message runtime message #:principal principal #:notify notify)}
uses the same validation and policy path, accepts a complete JSON-RPC request,
and returns the JSON-RPC outcome (or no response for a valid notification).
Both transports use this dispatch path. The transport chapters describe event
handles and synchronous client calls; only the explicit @tt{run-interaction}
runner follows MRTR/Tasks outcomes using the supplied callbacks.

@section{Declaration construction contracts}

The @tt{make-tool}, @tt{make-resource}, and @tt{make-prompt} factories check
metadata and callback contracts without executing handlers, defaults, completion
procedures, dependency expressions, or change expressions. The language forms
use these same factories. @tt{make-interface} rechecks raw descriptor structures
and copies, their arguments and schemas, and complete-interface references.
Runtime construction uses those same checks before recovering durable work.
Server identity and version are strings. The server constructor accepts @tt{#f}
for absent instructions and normalizes it to the empty-string default; other
instruction values must be strings. Argument names are
interned symbols, so their identity agrees with names decoded from JSON.
Repeated argument and shape-field wire names are rejected during expansion,
even when their lexical scopes differ; the diagnostic identifies the repeated
source binder rather than a generated constructor or accessor.

Tool and prompt handlers accept one bound-argument map. Resource handlers accept
one positional value per declared argument. Required keyword parameters are not
supplied by dispatch. Durable resources and prompts may use @tt{#f} for their
unused ordinary handler; tools retain a dispatcher procedure. A supplied workflow
must be a workflow descriptor. These checks do not execute or prove the result
of arbitrary handler code.

Tool annotations are JSON objects. The four standard hint fields are booleans
and @tt{title} is a string; unknown JSON-valued fields are retained. Inspection
rejects cyclic/non-JSON values and is bounded to 128 nesting levels and 50,000
values. The hints do not grant authority or establish effect guarantees.
Description and stored MIME-type fields are strings. Matchers and dependency
callbacks accept one argument, and committed-change callbacks accept two.

@section{Durable program construction contracts}

@tt{make-workflow}, declaration installation, and @tt{run-workflow} use the same
workflow checks before execution can create an instance. Names, versions and
fingerprints are nonempty strings. Stage identities are interned symbols; stage
procedures and an optional invocation-key procedure accept one environment or
argument map. A changes procedure accepts arguments and the completed result.

The checks validate schemas/codecs, distinct persistent identities, effect
policies, input-group names and declared control-flow destinations. Branches need
a destination. A reachable path cannot fall off the stage list, and completion
must be reachable from the first stage. This structural check does not execute
selectors or prove termination of arbitrary Racket computations. Effect policies
belong only on effect stages; adapter/destination fields must match their stage
kind.

Codec factories, registries and encode/decode entry points check identities,
versions, schemas and unary callbacks, including raw codec structures. Prompt
installation checks string codecs too. Checking a codec never calls its encoder
or decoder. Runtime encoding and decoding still validate the resulting data;
construction cannot establish arbitrary callback behavior.

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
Defines a reusable JSON Schema. Literal schemas receive expansion checks, and
invalid reader literals (including regular expressions, boxes and prefab
structures) produce errors at their source location. These checks also apply to
argument, output, shape and workflow stage schemas. Dynamic schemas receive
construction checks; arbitrary schema expressions are never evaluated by a
transformer.}
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
Native task workers use this same rendering path before publishing completion.
An embedded child awaiting input keeps the task in @tt{input_required};
@tt{tasks/update} resumes the retained rendering layout, including after a
restart, without recomputing the completed parent or completed children.
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
checked. New rendering records also retain bound parent arguments, so resuming
an embedded child or replaying a completed layout does not reevaluate defaults
or prompt codecs. Older @tt{render/3} records with explicit arguments remain
resumable; a record with an omitted default and no saved bindings fails with a
diagnostic because its original default value cannot be recovered.
SDK rendering markers carry a private Racket property; identical JSON
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
@declare-exporting[mcp #:use-sources (mcp/forms)]
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
non-tail position. Decisions, match subjects and selected pattern bindings are persisted; branch exits join
the following stages without re-evaluating the decision. @racket[let] blocks
persist initializers from left to right, each in the outer lexical environment,
then introduce their bindings for the block. Initializers must be replay-safe
JSON computations. Inner bindings may shadow outer bindings and do not escape
the block. @racket[begin] groups a sequence of stages. The private compiler retains
source-aware workflow nodes and checks branch/join destinations before emission.
Pattern predicates and @tt{app} computations run when the match snapshot is
constructed. After that checkpoint commits, later stages restore its bindings
without matching again, including across restart. Such computations must be
replay-safe until the checkpoint commits. Match-bound values use the built-in
JSON representation; closures, ports and other non-JSON values cannot cross this
boundary. Ordinary Racket helpers can perform computations confined to one stage.
Pattern variables are visible to workflow extension binding queries only within
their branch. The private compiler adapter parses each Racket match pattern once
and reuses that representation for code generation, preserving match-expander
hygiene without exposing Racket's pattern IR through the extension API.
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

Checkpoint computation, branch selection, branch joins, input-request construction,
completion handlers, and completion change-key callbacks retain this claim while running outside SQLite
transactions. Task polling and cancellation can proceed while these callbacks
block. Cancellation is checked again before their transitions commit; cancelled
completion does not record change-outbox entries. Callbacks can run again after
process loss before their transition commits, so persistent mutations belong in
declared effects. Checkpoint encoders and external-effect result encoders also run
outside SQLite. Cancellation prevents a checkpoint from advancing; an external
effect that already returned a committed outcome still records that outcome and
its change keys after cancellation, without changing the task's cancelled result.
Transactional effect encoders retain the mutation transaction so encoding failure
rolls back both mutation and stage completion. Effect-input preparation and its
environment decoding run outside SQLite for all three policies. Cancellation is
checked before adapter invocation or recording an external intent. An uncertain
manual effect rejects retry before input preparation runs again. Applications
must keep mutations inside the declared adapter; input preparation can run again
after process loss before its effect begins.

Single and grouped input requests are persisted after construction and before
input processing continues. Retries reuse this saved request data; they do not
re-enter the constructor. Cancellation during construction prevents the request
from being saved. Process loss before that save may rerun construction; after the
save, the pending request is available even if its response was never delivered.

Observed-outcome recovery codecs run without a SQLite transaction while retaining
the exclusive instance claim. Ownership and the pending effect are checked before
encoding. The repaired value, recovery journal, and change outbox commit together;
encoding failure or a stale revision commits none of them. Recovery cannot be
called inside an existing transaction on the same store, because it must own these
transaction boundaries.

@racket[#:execution task] selects Tasks instead of MRTR. Durable serving requires
an explicit state-file configuration. @racket[make-runtime] scans unexpired working
tasks and starts recovery workers. Awaiting-input and terminal tasks stay unchanged.
Use @racket[#:recover-tasks? #f] to defer startup and @racket[recover-runtime-tasks!]
to scan explicitly; the latter returns worker thread events. A missing executable
is a startup error. Incompatible executable versions fail through the workflow
compatibility check before execution.

A workflow's @racket[#:key] callback also applies to immediate task execution.
It runs once per initial invocation, outside SQLite transactions, using validated
arguments. Captured workflows compute it under their sealed executable resolver.
Task creation rejects a caller-owned transaction before key evaluation, so a
returned task handle cannot depend on a subsequent caller commit or rollback.
The key is scoped to the principal and workflow operation; reusing it with changed
arguments fails. Expired instances and incompatible executable versions are not
silently replaced.

Concurrent initial calls with the same key retrieve one task handle and its saved
creation response, even after the task completes or fails. A failed task remains
failed; repeating the key does not retry an uncertain effect. Synchronous and task
execution of a task-optional workflow share the keyed workflow execution. The
task receipt is stored separately so attaching a task cannot disrupt an in-flight
synchronous stage. Without a key, initial calls still create independent work.
This does not retroactively deduplicate immediate tasks created by older builds
that did not record their declared keys.

@defform[(task-boundary stage-id)]{
Declares a stable stage identity at which a task-enabled workflow hands off to
background execution. It is valid only in the workflow stage grammar; it does not
bind a Racket value. Duplicate stage identities and uses hidden in ordinary host
expressions are expansion errors. Like other workflow stages, the boundary is
included in manifests and executable compatibility fingerprints.

A task workflow containing a boundary runs its prefix synchronously as durable
MRTR. Its input-required results contain no task handle. Reaching the first
boundary on the selected branch atomically persists a task and its handoff receipt,
then returns the task result without an MRTR state token. Checkpoints and accepted
input carry into the task. A branch that completes before reaching a boundary
returns its ordinary result; use this to preserve decline or cancellation outcomes.

Repeating an accepted continuation returns the same recorded task handle, including
while the task runs and after it finishes. Conflicting input, changed arguments,
foreign principals, expiry and incompatible workflow code remain errors. The task
inherits the preparation's expiry. Process restart recovers working tasks through
the ordinary runtime scan. No initial invocation is automatically replayed: without
a declared workflow key, another initial request creates another preparation.

Without a boundary, task execution retains its immediate-start behavior. With
@racket[#:execution task-optional] and no client Tasks capability, boundaries are
passed synchronously and the entire workflow remains MRTR. If a later MRTR
continuation advertises Tasks support, it resumes that saved execution with its
submitted responses. Without a boundary it continues synchronously; with a
boundary it can hand off at that boundary. It never creates a fresh execution
in place of the continuation. Subsequent boundaries
inside an already-started task do not create nested tasks. A nested local workflow
does not inherit the parent's handoff factory.
}

@tt{examples/prepared-task.rkt} demonstrates a name request followed by background
work. The ordinary data API uses a @tt{workflow-stage} of kind @tt{'task-boundary},
with @racket[Any], a procedure returning @racket[json-null], and @racket[#f] adapter
and policy fields. The boundary does not invoke that procedure or save a value.
@tt{start-workflow-task} accepts @racket[#:state] and
@racket[#:responses] for the preparation's MRTR retries.

Task execution omits absent optional arguments before computing invocation keys
or saving arguments, just as synchronous workflow execution does. Explicit false
and JSON null values remain present; defaults are evaluated once during binding.
Runtime workers resume the saved bound argument map. They validate its domain
values without applying the external input schema again to defaulted fields.
Local task completion checks the complete tool-result shape and the tool's declared
output schema before publishing a completed status. Invalid output fails the task;
an intentional @tt{isError} result is exempt from the structured-output schema.
Validation does not replay completed workflow effects.

The lower-level task APIs accept @racket[#:output-schema].
@tt{start-workflow-task} defaults to no output schema and saves the supplied schema
with the task. @tt{resume-task!}, @tt{update-task!}, and @tt{retry-recovered-task!}
use that saved schema unless explicitly overridden. Runtime entry points supply
the current tool descriptor's schema, including for legacy records without a saved
schema. Polling through the runtime also rejects invalid legacy completed results
without rewriting their stored history.
These APIs execute the supplied workflow and adapters even when called by an
ordinary runtime handler or from another task worker. The runtime's installed-tool
executor applies only to tasks launched through its own task entry points.

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
policy before acknowledging the accepted IDs.
For bridged upstream tasks, registration and notification delivery also check
the originating @tt{tools/call} permission with its saved name and arguments,
as polling does. These checks do not contact the upstream server. Native task
read subscriptions retain their task-read policy.
Committed transitions emit @tt{notifications/tasks} with the complete detailed task, tagged with the
subscription request ID. Notifications are bounded hints: after reconnecting or
overflow, poll @tt{tasks/get}; there is no notification replay. Terminal no-op
cancellation does not emit a new transition. The exhaustive failure-boundary
matrix remains open.

@section{Transports, policy, and ownership}
@subsection{Stdio}
@defmodule[mcp/stdio]
@defproc[(make-stdio-client [input input-port?] [output output-port?]
                            [#:close-ports? close-ports? boolean? #t]
                            [#:notification-limit notification-limit exact-positive-integer? 64]
                            [#:request-limit request-limit exact-positive-integer? 1024]
                            [#:progress-token-limit token-limit exact-positive-integer? 1024]
                            [#:timeout timeout (or/c #f (and/c rational? positive?)) 30]
                            [#:outbound-limit outbound-limit exact-positive-integer? 64])
         any/c]{
Creates an opaque stdio client and starts its reader and serialized writer.
Pass the returned value to @racket[client-request], @racket[client-call] and
@racket[client-close!]. Limits and ownership are described below.
}
@defproc[(request-handle? [value any/c]) boolean?]{
Recognizes request handles returned by the stdio and HTTP request APIs. A handle
is an event: @racket[sync] returns its response hash or failure exception value.
Synchronizing the same completed handle again returns its recorded outcome.
}
@defproc[(request-handle-id [handle request-handle?]) any/c]{
Returns the JSON-RPC request ID assigned to the handle.
}
@defproc[(request-handle-notifications [handle request-handle?]) async-channel?]{
Returns the bounded channel of notification messages for this request. Receive
from it with @racket[async-channel-get] or synchronize on the channel. Completion
of the request is reported by the handle event, not by a channel sentinel; wait
on both when consuming notifications until completion.
}
@defproc[(request-cancel! [handle request-handle?]) void?]{
Cancels an active request locally and initiates transport cancellation. The
operation does not wait for acknowledgement and leaves completed handles intact.
}
@defproc[(client-close! [client any/c]
                      [reason any/c (exn:fail "Client closed" (current-continuation-marks))])
         void?]{
Closes a client returned by @racket[make-stdio-client], settles its outstanding
handles and releases owned resources. Repeated calls leave the first outcome
intact. An exception reason is retained; another value is wrapped in
@racket[exn:fail:stdio].
}
@racket[make-stdio-client] accepts input/output ports and owns them by default.
Explicit close, EOF, or a decoding/protocol failure resolves all pending handles,
stops the reader, and closes both ports. With @racket[#:close-ports? #f], the
caller retains port ownership; explicit close still stops the reader. Writes use
a separate lock so a blocked peer cannot prevent pending-handle resolution.
Non-break failures raised by custom port procedures also close the client.
Existing exception objects retain their identity. Non-exception values, including
@racket[#f], become @racket[exn:fail:stdio] values; @racket[exn:fail:stdio-cause]
retains the original raised value. This ensures synchronous calls raise failures
instead of returning them as protocol results. Cleanup attempts both owned ports
and stops client workers even when a port's close procedure raises a value.
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
@racket[exn:fail:request-cancelled], carrying its @racket[request-handle-id], and queues
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

Both clients validate subscription notification IDs, acknowledgement ordering,
and the acknowledged subset of the requested filter before delivering messages.
Core list/resource notifications and Tasks notifications must match the accepted
filter. Partial or empty acceptance remains visible on the notification channel;
it is not an automatic retry. Unknown extension filter values must match exactly,
since the client cannot infer their subset semantics. A malformed subscription
notification fails the HTTP request; on stdio it closes the client under the
shared reader's protocol-error policy. Late notifications for finished stdio
requests are discarded. Progress and cancellation retain their separate routing.
A successful subscription result must follow acknowledgement, have the
@tt{complete} discriminator (including the protocol's missing-field default),
and carry the matching subscription ID. Both HTTP JSON and SSE outcomes receive
this check. A protocol error may reject establishment before acknowledgement;
matching server cancellation notifications remain accepted under the recorded
specification interpretation.

@tt{close-subscriptions!} accepts a hub and optional @tt{#:matches?} predicate
receiving each listener's principal and accepted filter. The default selects all
listeners. An optional @tt{#:error-message} string closes selected listeners with
error @tt{-32000}; the default @racket[#f] produces graceful completion. The first
recorded failure reason is retained, including queue overflow. Selection executes
outside the hub lock; closure signals listeners without performing transport I/O.

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
Non-break failures from request workers, including application network security
guards, also settle the handle and release its progress-token reservation.
Existing exception objects retain their identity. Other raised values, including
@racket[#f], become @racket[exn:fail:http:transport] exceptions whose
@racket[exn:fail:http:transport-cause] field retains the original value. A
synchronous call raises the exception instead of returning it as a protocol
outcome. The request custodian is reaped when its worker exits.
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

For native confidential-client authentication, supply
@racket[#:client-authentication] as a hash from issuer strings to
@racket[oauth-client-authentication] values from @racketmodname[mcp/oauth-http].
The selected registration's issuer and client ID must match the configured value,
and discovery metadata must support its authentication method. Both authorization
code exchange and token refresh use that configuration. Credentials configured
for another issuer are never selected. The authorizer snapshots the mapping.
A custom @racket[#:exchange] owns its authentication and cannot be combined with
a nonempty native authentication mapping.

@racket[#:allow-loopback-http? #t] permits HTTP identifiers and endpoints only on
@tt{localhost}, @tt{127.0.0.1}, and @tt{::1} during this authorizer's execution.
This explicit local-fixture option defaults to @racket[#f]; HTTPS remains required
otherwise. Client ID Metadata Document URLs remain HTTPS even with the option.
It does not change another authorizer's policy or rewrite received URLs.

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

@racket[client-id-metadata-document] advertises both @tt{authorization_code} and
@tt{refresh_token} grants by default. Applications that do not want refresh tokens
can set @tt{grant_types} to only @tt{authorization_code} through @racket[#:extra].
Advertising support does not guarantee issuance; responses without refresh tokens
remain valid. The runner does not automatically add the optional
@tt{offline_access} scope.

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
explicitly permits HTTP on @tt{localhost}, @tt{127.0.0.1}, and @tt{::1} for local
development fixtures. Standalone discovery functions retain their HTTPS checks.

@racket[(oauth-client-authentication issuer client-id method secret)] creates an
opaque configuration whose strings are copied to immutable storage. The method
is @racket['client_secret_basic], @racket['client_secret_post], or @racket['none];
the first two require a string secret, and @racket['none] requires @racket[#f].
The predicate and issuer, client-ID and method accessors are exported; a secret
accessor is not. Default printing does not expose the secret.

To use a configuration directly, pass it as @racket[#:client-authentication] to
@racket[make-oauth-http-adapters] together with @racket[#:token-endpoint]. The
exchange callback rejects a different endpoint, a conflicting client ID, or
additional authentication fields before sending a request. Basic authentication
form-encodes the ID and secret separately before Base64 encoding; post
authentication puts them in the form body. Neither attaches authentication to
metadata fetches. The low-level adapter binds an endpoint; the authorizer also
checks issuer, registration and advertised method.

OAuth functions create PKCE requests and validate state and issuer during exchange.
A present authorization-response @tt{iss} must exactly match the recorded issuer,
without URL normalization. A missing @tt{iss} is rejected when the authorization
server advertises @tt{authorization_response_iss_parameter_supported} as true;
when that metadata field is false or absent, the response may proceed through
the remaining state, error, and authorization-code checks.
Applications can use the native fetch/exchange callbacks or supply their own.
Browser interaction and credential persistence remain application callbacks.
Hosted authorization services are outside the package scope. Dynamic client
registration and its durable registration store are provided by
@tt{mcp/oauth-registration} and @tt{mcp/oauth-registration-store}.

@subsection{Explicit interaction runner}
@defmodule[mcp/interaction]
@defproc[(run-interaction [request procedure?] [method string?] [params hash?]
                          [#:elicit elicit procedure?]
                          [#:navigate navigate procedure?]
                          [#:max-rounds max-rounds exact-positive-integer? 100]
                          [#:wait wait procedure? (lambda (milliseconds)
                                                   (sync (alarm-evt (+ (current-inexact-milliseconds) milliseconds))))])
         hash?]{
Runs one application-authorized interaction, following MRTR continuations and
Tasks through the supplied request procedure. The request callback accepts two
arguments, a method string and a parameter hash, and must issue a fresh JSON-RPC
ID on every call. It returns a result hash or a JSON-RPC response hash. The runner
returns the final outcome in that same representation; a terminal Tasks outcome
remains the task snapshot, including its nested operation result.

The elicitation and navigation callbacks each accept one elicitation parameter
hash and return an input-response hash. Navigation handles URL elicitation; the
elicitation callback handles forms. The wait callback accepts a polling interval
in milliseconds and its result is ignored. The default waits on a Racket alarm
event. Callbacks execute synchronously in the calling thread, so applications
control UI interaction, credentials and any surrounding cancellation scope.
Low-level client calls return protocol outcomes directly; only this explicit runner
performs follow-up requests. Supply @racket[#:elicit] and @racket[#:navigate]
callbacks returning input responses. Decline and cancellation responses are retained.
Exceptions and protocol errors stop the interaction without replaying the request.
Each elicitation request is validated before invoking its callback. Accepted form
responses are checked against their schema and the declared @tt{date},
@tt{date-time}, @tt{email}, and @tt{uri} formats before sending a retry or task
update. Invalid callback output raises an error without sending that response.

The runner echoes opaque request state exactly, omits it when absent, and replaces
previous-round input responses. It supports input-only and state-only results;
malformed input-required results fail before retry. Missing @tt{resultType} means
@tt{complete} under the protocol's client fallback rule. Tasks are polled and updated
through the same callback, which must carry the application's capabilities and
credentials. @racket[#:wait] supplies polling waits; @racket[#:max-rounds] is a
positive integer, default 100, bounding loop rounds rather than individual messages.
}

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
not a hash or proof of procedure equivalence. Captured application builds include
observed imported helper code; ordinary uncaptured workflows require an explicit
build identity to cover changes outside their generated stages.
Prompt and resource workflow renaming preserves both declared identities and
captured executable context. Legacy prompt/resource continuations saved with
discarded build identity are rejected as incompatible before accepting input or
advancing stages; their missing provenance cannot be inferred safely. Before
upgrading, finish those continuations under their originating application build,
or retain the records for explicit application-level recovery. No automatic
fingerprint migration or effect replay is performed.
New tasks additionally retain the published tool name so sibling
mounts resolve their own bindings during updates and startup recovery. Failed tasks
remain terminal when their workflow requires recovery.

These replacements are named effect bindings, not interception of arbitrary Racket
I/O. Interface restrictions enforce the declared adapter surface; they do not
sandbox arbitrary application code. Upstream MRTR/Tasks bridging is described below.

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
while local lookup uses the transformed declaration. Without an explicitly
configured bridge, MRTR and Tasks outcomes still fail explicitly.

@tt{upstream-resource-change-keys}, exported by @tt{mcp/upstream}, accepts the
installed upstream interface and a URI in that interface's namespace. It resolves
exactly one resource and returns its JSON dependency-key list. Unknown URIs and
resources without upstream keys fail explicitly. Generated resources and templates
declare these dependencies automatically. Views retain them, so resolving a remote
URI against the original interface or its corresponding local URI against a view
produces the same keys. Resolution does not read the resource or call the peer.

An application receiving a resource change from that upstream can pass these keys
to @tt{runtime-report-change!} with the local principal and runtime. Invalidation
precedes local notifications, which use the mounted URI and the existing local
authorization path. Private caches remain principal-partitioned. Each call to
@tt{make-upstream-interface} allocates a separate freshness identity, even for
identical snapshots and URI strings. Retain the installed interface for subsequent
change reports; these keys belong to that installation and are not portable
across reconstructed interfaces. Resource TTL remains zero unless explicitly
configured otherwise. This dependency API does not itself open or reconnect an
upstream subscription, and it does not infer changes in remote systems.

@subsubsection{Scoped upstream resource subscriptions}
@defmodule[mcp/upstream-subscription]

@tt{call-with-upstream-resource-subscription} takes a local runtime, the original
installed upstream interface, its pinned snapshot, an asynchronous request
callback, a nonempty list of remote resource URIs, and a consumer procedure.
Supply the local notification owner with @tt{#:principal}. The request callback
accepts a method and parameters and returns an SDK @tt{request-handle}; it owns
upstream connection configuration, metadata and credentials. It should return
promptly and leave the subscription request without an ordinary request deadline.

The runner resolves the URIs before network requests, copies the snapshot, and
verifies discovery and declarations before listening. It invokes the consumer only
after a correctly tagged acknowledgement whose accepted filter is a subset of the
requested resource URIs. The consumer receives an
@tt{upstream-resource-subscription?} event. Its
@tt{upstream-resource-subscription-accepted} accessor returns the accepted remote
URI list. A worker drains changes through @tt{runtime-report-change!}, retaining
the local principal's cache partition, mapped URIs and notification policy.
Unexpected methods, unaccepted URIs and incorrect subscription tags fail the stream.

Synchronizing the event returns the terminal upstream protocol outcome or an
exception value. Setup failures raise before the consumer runs. Completion waits
for already queued notifications to be processed; a retained event keeps the same
terminal outcome. @tt{stop-upstream-resource-subscription!} cancels the upstream
request. Returning or escaping from the consumer cancels that request and releases
the forwarding worker while preserving the consumer's result or raised value.
Explicit stop and scope exit abandon queued changes. A forwarding pass already
executing may finish, but the worker observes its local stop signal before starting
another pass. Normal upstream completion continues to drain queued changes.
The borrowed upstream client retains its own lifetime.
Nest this scope inside the lifetime of the local runtime and upstream client.

By default, ending an acknowledged feed also terminates matching local listeners
for the supplied principal, using only the accepted upstream filter and the
installed resource mappings. Graceful completion and explicit stop produce a
completion result; unexpected loss produces error @tt{-32000}, instructing the
client to re-listen and refresh. Affected private cache entries are invalidated
without inventing committed-change notifications. An empty accepted filter
affects no local listeners or cache entries. If application dependency calculation
fails or exceeds worker cleanup time, termination conservatively closes all
resource listeners for that principal. Cleanup does not repeat an interrupted
dependency callback. Set @tt{#:propagate-loss? #f} when the application owns
downstream listener recovery and termination itself.

@tt{#:timeout} defaults to five seconds and bounds each snapshot request,
acknowledgement wait and worker cleanup. It is not the lifetime of an acknowledged
subscription. Transport loss and native queue overflow remain observable failures.
The application handles the terminal event, refreshes its state as appropriate,
and explicitly starts a new scope to listen again. Reconnection does not replay
subscriptions automatically. This runner handles resource updates. The task runner
below shares its stream lifecycle. Upstream list changes require separate
integration.

@subsubsection{Scoped upstream task subscriptions}

@tt{call-with-upstream-task-subscription} takes a local runtime, a pinned upstream
snapshot, an asynchronous request callback, a nonempty list of local task IDs,
and a consumer procedure. Supply @tt{#:principal} and @tt{#:capabilities} for the
local task owner. @tt{#:timeout} has the same per-operation meaning as the resource
runner above. The callback owns the authenticated upstream connection and its
metadata; all requested tasks must belong to that peer and credential context.

Before upstream I/O, each task is checked through runtime authorization, ownership,
expiry, stored credentials and the installed interface's snapshot. The runner
resolves persisted remote IDs, verifies the pinned peer, and requests a task-ID
filter. Only a correctly tagged acknowledgement accepting a subset of those IDs
allows the consumer to run. The consumer receives an
@tt{upstream-task-subscription?} event; @tt{upstream-task-subscription-accepted}
returns accepted local IDs in the caller's original order, without duplicates.
Multiple local handles for one remote task receive the same accepted observation.

Accepted @tt{notifications/tasks} messages pass through
@racket[runtime-observe-upstream-task!]. Each delivery rechecks local policy and
credentials, validates and persists the detail, and notifies local subscribers
with local IDs, input mappings and mounted resource links. Notifications do not
poll the peer. Invalid methods, tags, filters, details or revoked access terminate
the forwarder with an exception outcome and cancel its upstream subscription.

@tt{stop-upstream-task-subscription!}, scope exit, graceful completion, transport
loss and queue overflow have the same behavior as the resource runner. By default,
termination closes local listeners whose accepted task filters overlap the
accepted translated IDs, for the same principal. It does not cancel tasks,
change their persisted states or revisions, or fabricate task notifications.
An empty accepted filter affects no local listeners. The same
@tt{#:propagate-loss? #f} option leaves downstream listener lifetimes under
application control. Applications must handle the terminal event and explicitly
refresh/re-listen after loss.
Independent control requests and notification streams have no shared protocol
sequence number: applications must coordinate them and reconcile uncertain or
stale observations. This runner does not retry task mutations or silently repair
a recovery-required task.

An acknowledged input update retains a fingerprint of the consumed remote input
snapshot. A delayed notification matching that superseded snapshot fails the
forwarder without reopening the input round. This check survives storage reopen
and also applies when the notification waits behind an in-flight update. An
explicit @tt{tasks/get} poll can establish a fresh round, including when a peer
reuses identical input IDs and coarse timestamps; subsequent duplicate notices
for that newly established round are accepted. This detects known consumed
snapshots, not arbitrary timestamp ordering. Input updates consumed by older SDK
versions without these fingerprints cannot be retroactively classified.

@subsubsection{Durable upstream MRTR}
@defmodule[mcp/upstream #:use-sources (mcp/upstream-bridge mcp/private/upstream-task)]
@defproc[(upstream-bridge? [value any/c]) boolean?]{
Returns whether the value is an upstream bridge configuration.
}
@defproc[(make-upstream-bridge [#:identity identity string?]
                              [#:version version string?]
                              [#:credential-id credential-id procedure?]
                              [#:ttl ttl exact-positive-integer? 86400]
                              [#:max-rounds rounds exact-positive-integer? 100]
                              [#:max-bytes bytes exact-positive-integer? 1048576]) upstream-bridge?]{
Constructs an inert bridge configuration. Pass it as @racket[#:bridge] to
@tt{make-upstream-interface}, and supply a store to the local runtime. Use an
explicit SQLite state path for durability; memory storage remains ephemeral.
The serving command requires @tt{--state} before starting any transport when
the published interface contains a bridge handler.
Identity and version are nonempty strings describing the upstream service and
adapter implementation. Change the version when callback behavior changes.

The credential callback receives the local principal on each invocation and
returns a nonempty stable string identifying the upstream account/credential
context. Use an account or issuer/subject identifier, never a bearer token. The
request callback still owns the separate upstream credentials, connection, and
request metadata. It should advertise only input capabilities it can bridge to
the local client. The SDK does not copy local bearer credentials upstream.
}

The bridge supports tools, resource reads, and prompts. It binds local opaque
continuation tokens to the principal, credential identity, original request,
pinned snapshot, adapter version and expiry. Input IDs are translated independently
on each round; remote request-state tokens are retained in storage and are not
used as local wire handles. Partial responses accumulate locally before the next
upstream request. Decline and cancellation answers are forwarded unchanged.
Input-only and state-only MRTR rounds are supported.

Each upstream call has a committed intent before network execution. Its response
is persisted before translation. Concurrent retries share one instance claim;
recorded results are reused without repeating the upstream call. If a call may
have executed but its result was not saved, an
@tt{exn:fail:upstream-recovery} exposes its local @tt{handle} and original local
@tt{cause} to operator code. Normal wire dispatch does not expose that cause.
No uncertain call is automatically retried.

Elicitation request structure is validated using a mechanically extracted subset
of the pinned MCP schema and the native validator. Workflow inputs receive the
same check before being persisted. URL-mode requests require URI syntax, and
accepted form responses enforce the four supported string formats. The offline command
@tt{python3 scripts/extract-elicitation-schema.py} refreshes the extraction after
an explicit pin change; @tt{--check} verifies it during the regular test command.

These elicitation checks use native Racket code and the syntax rules from
@hyperlink["https://www.rfc-editor.org/rfc/rfc3339.html"]{RFC 3339},
@hyperlink["https://www.rfc-editor.org/rfc/rfc3986.html"]{RFC 3986}, and
@hyperlink["https://www.rfc-editor.org/rfc/rfc5321.html"]{RFC 5321}.
They do not query DNS, navigate to a URI, or verify mailbox existence. Date-time
validation checks leap-second placement at a UTC month-end with offset conversion;
it does not consult historical or future leap-second bulletins. URI validation
uses the generic RFC 3986 grammar, including IPv6 and IPvFuture literals;
scheme-specific navigation and authorization policies remain application concerns.
General JSON Schema @tt{format} retains annotation semantics. The separate
@tt{tests/elicitation-format-suite.rkt} runs 242 pinned optional format cases
against these elicitation assertions; this does not enable the full optional
JSON Schema format-assertion vocabulary.

Upstream tool Tasks are translated when the pinned discovery advertises the
Tasks extension and a bridge is configured, as described below. Other unsupported
Tasks outcomes are retained for inspection and rejected without exposing remote
handles as local handles. Upstream subscription forwarding is not implemented yet. The pinned MCP revision permits
MRTR only for tools, resource reads, and prompts; completion MRTR is forbidden
and rejected. Complete-result completion forwarding remains available.

@defproc[(bridge-upstream-request [bridge upstream-bridge?] [store any/c]
                                  [snapshot hash?] [request procedure?] [method string?] [params hash?]
                                  [#:principal principal string?] [#:credential-id credential string?]
                                  [#:state state any/c #f] [#:responses responses hash? (hasheq)]
                                  [#:capabilities capabilities hash? (hasheq)] [#:key key any/c #f]
                                  [#:verify verify procedure? void]
                                  [#:cancelled? cancelled? procedure? (lambda () #f)]) hash?]{
Low-level entry point used by the interface adapter. Returns a normalized
@tt{result} or @tt{error} outcome. The request callback accepts a method and parameter
object. The original parameters must omit @tt{requestState} and @tt{inputResponses};
pass local continuation fields through the corresponding keywords. An optional
invocation key deduplicates initial calls; without one, each initial call is new.

The zero-argument verify callback runs outside a transaction before each actual
outbound call, but does not run when serving a recorded result. The interface
factory installs its pinned-snapshot compatibility check here; direct callers
must supply their own check. The principal is the local canonical owner key and
the credential string identifies the separately configured upstream context.
Byte limits cover original arguments, responses, and accumulated stored state.
}

@defproc[(recover-upstream-request! [bridge upstream-bridge?] [store any/c]
                                   [snapshot hash?] [handle string?]
                                   [#:principal principal string?] [#:credential-id credential string?]
                                   [#:action action symbol?] [#:outcome outcome any/c #f]
                                   [#:capabilities capabilities hash? (hasheq)]) hash?]{
Local operator API for an uncertain or received-but-untranslated interaction.
Authorize this action in the application before calling it; no recovery wire
method is installed. Recovery verifies the owner, credential, snapshot, version,
and expiry and refuses to race an active request.

@tt{'outcome} records an independently observed protocol response/result and
returns its local translation. @tt{'retry} journals permission to send the exact
saved outbound request again and returns an input-required outcome containing a
local continuation token; the recovery call itself does not send it. @tt{'abandon}
records a terminal error. Terminal interactions cannot be changed by this API.
No action is an exactly-once guarantee. Local @tt{list-instances} and
@tt{instance-events} provide inspection of saved state and the recovery journal.
}


@subsubsection{Upstream tool Tasks}

A bridged tool interface whose pinned discovery advertises
@tt{io.modelcontextprotocol/tasks} can return a local task receipt. The runtime
advertises the installed Tasks facility when storage is configured. The upstream
request callback remains responsible for its connection, separate credentials,
and matching request capabilities; it must not advertise capabilities the local
client cannot fulfill. The bridge checks local Tasks support before publishing
or adopting a task handle.

An upstream missing-client-capability error retains code @tt{-32021} and its
error data through the adapter, so the caller can inspect the required capability.
It is not converted to a generic internal error. A keyed durable invocation that
recorded this rejection returns the recorded rejection on retry; it does not
automatically replay the upstream call after capabilities change.

The local task record is persisted before its receipt is returned. Repeated
keyed initial calls return the original receipt. Polling, input updates, and
cancellation resolve the originating tool through the mounted interface and
recheck local ownership, operation authorization, credential identity, snapshot,
version, and expiry before contacting the peer. Removing the tool prevents task
access through that interface. Remote workers remain owned by the peer; local
runtime startup does not execute them as Racket workflows.

Task input IDs are opaque local identifiers. Partial answers accumulate before
one upstream update; identical retries do not resend accepted updates and
conflicting answers fail. Task details and completed tool results retain the
local task ID and mounted resource links. Successful structured task results are
checked against the tool's output schema. Recorded terminal tasks are immutable
and repeated polls do not contact the peer. Initial local retention is bounded
by the bridge expiry and the peer's declared finite TTL, rounded to the store's
second resolution; a peer may still expire its own task independently.

Read-only polling failures can be retried. Updates and cancellations persist an
intent before sending, then a receipt before advancing. If a mutation's outcome
is lost or its worker is terminated, the next local operation records a failed
task with an explicit recovery-required diagnostic. It never automatically sends
the mutation again. An acknowledged cancellation is followed by polling the
peer's actual status, preserving a completion/cancellation race. The local @racket[recover-upstream-task!] API records an independently observed
upstream task outcome and creates a replacement handle. The separate
@racket[retry-upstream-task!] API explicitly authorizes a resend of an uncertain
mutation. Native-workflow recovery APIs do not revive an upstream task.

Subscribers to local task IDs receive committed observed changes, including
translated completed results. Registration, publication, and queued delivery
recheck the reader's credential identity and pinned task binding locally, without
contacting the peer. This currently reports changes observed through
local polling, control requests, and explicit observations. The scoped task runner
can supply observations from a live upstream subscription. Broader concurrent and
fault-injection coverage and independent task-bridge interoperability remain
release gates.

@subsubsection{Accepting upstream task observations}

@declare-exporting[mcp/runtime]
@defproc[(runtime-observe-upstream-task! [runtime any/c] [task-id string?]
                                      [detail hash?] [#:principal principal any/c]
                                      [#:capabilities capabilities hash?]) hash?]{
Accepts an authenticated upstream task status notification's parameters for an
existing local bridged task. The application must supply the corresponding local
task ID and obtain the detail from its trusted upstream connection. This is a
local integration API; no MCP request parameter can install an observation.
It performs the same ownership, authorization, credential identity, executable
compatibility, expiry and capability checks as local task polling, without
polling or mutating the upstream peer.

The detail's remote task ID and Tasks schema must match the stored translation.
Successful tool output is validated before persistence. Input identifiers and
resource links are translated, committed changes notify local subscribers, and
the returned detail uses the local task ID. Upstream subscription metadata is
discarded; local notifications receive their own subscription metadata.
Identical observations do not create another revision or notification.

Recorded terminal outcomes remain immutable. An uncertain prior mutation still
requires explicit recovery; an observation cannot silently repair or replay it.
The caller owns subscription establishment and ordering of observations against
its control requests. This API neither establishes a stream nor provides a
protocol sequence number for resolving stale, out-of-order observations.
}


@subsubsection{Recovering uncertain upstream tasks}

@declare-exporting[mcp/upstream #:use-sources (mcp/private/upstream-task mcp/upstream)]
@defproc[(recover-upstream-task! [bridge upstream-bridge?] [store any/c]
                                [snapshot hash?] [task-id string?]
                                [#:principal principal string?] [#:credential-id credential string?]
                                [#:outcome outcome hash?] [#:authorize authorize procedure? void]) hash?]{
Local operator API for replacing a task whose upstream mutation became uncertain.
The application must authorize repair; the optional zero-argument authorization
callback runs once per call, outside storage transactions. No wire recovery method
is installed. Calls inside a caller-owned store transaction are rejected before
authorization or state changes.

Supply an independently observed @tt{tasks/get} result, directly or inside a
protocol result envelope, for the same remote task ID. The operation validates
the local owner, credential identity, pinned snapshot/version, task expiry, and
observed result. It refuses to race an active task worker. If a terminated worker
left an intent before a poll recorded failure, repair first records that failure.

The old task stays failed. A new local task and its creation receipt commit with
journal links on both records. Its expiry cannot extend the old handle's
retention. Repeating an identical repair returns the same receipt, including
after SQLite reopen; a different observation for the same repair is rejected.
Pending input receives fresh local IDs. Get the new task through its originating
interface to apply normal authorization, presentation and output contracts.

This call performs no upstream requests and never retries a mutation. The supplied
observation is the operator's responsibility; it is not an exactly-once guarantee.
A normal upstream failure without an uncertain local mutation is not eligible.
}


@defproc[(retry-upstream-task! [bridge upstream-bridge?] [store any/c]
                              [snapshot hash?] [request procedure?] [task-id string?]
                              [#:principal principal string?] [#:credential-id credential string?]
                              [#:authorize authorize procedure? void]) hash?]{
Local operator action authorizing one retry of an uncertain task update or
cancellation. The application must authorize this action; the zero-argument
callback runs outside storage transactions on every call. The original failed
task is never revived. Ownership, credential, pinned snapshot/version, expiry,
and active-worker checks use the same path as observed-outcome repair.

A replacement handle and retry authorization commit before dispatch. The supplied
request procedure accepts method and parameter objects and owns the separately
configured upstream connection, credentials, and request metadata. Before an
actual resend, the SDK verifies the peer against the pinned snapshot. It then
records an outbound intent and resends the exact stored mutation parameters.
There is no inference that an earlier lost response meant the mutation failed.

Repeated and concurrent calls for the same original task reuse one replacement
receipt and do not authorize another resend. If verification fails or execution
stops before dispatch, the recorded authorization remains pending; another
operator call can finish it. Ordinary task polling only reports that pending
state and does not dispatch the mutation. Ordinary update/cancel calls cannot
bypass pending operator dispatch.

Once an outbound intent exists, another interrupted/lost outcome fails the new
task rather than replaying it. The retry call may raise; repeating it with the
same original task ID retrieves the recorded replacement receipt without sending
again. Journal links on the original task also expose its replacement for local
inspection. A further retry requires a fresh explicit repair of that new failed
handle. Successful dispatch returns the immutable creation receipt; poll that
handle normally for the peer's eventual result.

Observed-outcome repair and retry authorization are mutually exclusive decisions
for one failed handle. A conflicting decision is rejected. Neither API provides
an exactly-once guarantee or a wire recovery method.
}

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

@tt{examples/collections.rkt} uses the separately imported @tt{collection} form
twice. It publishes @tt{search-books} and @tt{search-articles}, resources at
@tt{book:///{id}} and @tt{article:///{id}}, and independent completion for each
template's @tt{id} argument. Run it with @tt{racket examples/collections.rkt}.
The extension's @tt{#:entries} expression is evaluated once per invocation when
the application module is instantiated; generated handlers retain that value.
Each invocation's generated helper is hygienic. The native extension regression
also checks renamed imports and completion after a view remaps the resource URI.
The official Go interoperability runner exercises the generated public interface
without reading compiler metadata.

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
the checked module binding metadata is unavailable there. Lexically visible
references and explicit reference declarations are checked against the composed
interface; computed references retain runtime target and ambiguity checks.
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
entries dependent on changed children.

A dependency key is scoped to its owner; using the same key for two principals
does not grant access or share a cached representation. For application data
shared by several owners, the application supplies its sharing relation explicitly.
Record one @racket[record-committed-change!] per affected owner in the same
@racket[store-transaction] as the shared mutation, then call
@racket[runtime-drain-changes!] after commit. Include former owners whose retained
entries must be invalidated after revocation. Delivery rechecks each subscriber's
current authorization, so invalidation does not grant notification access.

An external committed-change feed can likewise emit one @tt{external-change}
per affected owner, with distinct stable event IDs. The existing feed transaction
records the whole page and cursor together. For ephemeral integrations,
@racket[runtime-report-change!] can be called for each owner after commit; durable
applications should use the outbox or reconciled feed to survive interrupted
publication. The SDK does not discover an application's sharing relation or
broadcast private dependency keys to all principals. List pages remain private
with zero TTL; a new listing refreshes them, while an existing cursor retains its
snapshot. MRTR input-required results and continuation reads remain uncached.

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
The separate @tt{tests/schema-regex-suite.rkt} runner checks 86 pinned optional
ECMAScript/non-BMP cases; both local and portable CI run it independently of the
core suite. Unsupported cases count as failures, not skips.

The native pattern translator handles control/hex/Unicode escapes, scalar
surrogate pairs, ASCII digit/word classes, Unicode whitespace and its complement,
empty classes, dot's line-terminator exclusions, and the supported Unicode
category aliases (including @tt{Letter} and @tt{digit}). Translation respects
escaped literals and character-class boundaries. Unicode whitespace follows the
@hyperlink["https://tc39.es/ecma262/multipage/text-processing.html#sec-patterns"]{ECMAScript
WhiteSpace and LineTerminator rules}. This is a tested compatibility profile,
not a complete ECMAScript regex implementation: backreferences, named groups,
script/binary property families, non-scalar
Unicode escapes and some lookbehind forms are unsupported. Racket-only escapes,
group modifiers and malformed brace syntax do not silently gain native meanings.
Regex work remains subject to the documented CPU-budget limitation.
The native regressions check whitespace and its complement across all 1,112,064
Unicode scalar values. Character-class unions and negation are compiled
explicitly; positive ranges are split at UTF-8 suffix boundaries to avoid a
reproduced Racket 9.2/9.3 range-compilation defect (for example, native
@tt{[U+FF00-U+FFFF]} excludes U+FF40). Supported category escapes also work inside
these character classes.

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
 handler expressions. Resource and prompt bindings also export their static name and argument
 names through lexical transformer values. Imported and re-exported declarations
 retain argument checks through renaming; aliases of one imported declaration cannot
 define duplicate completion routes. Their manifest target records the original
 name and kind without instantiating the provider or its handlers. Host-supplied
 target information that the compiler cannot establish is marked
 dynamic. Interface construction checks target
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

@section{URI templates and inverse adapters}

@tt{mcp/uri-template} provides @tt{check-uri-template!},
@tt{uri-template-variables}, @tt{uri-template-expand}, and
@tt{uri-template-matcher}. Parsing follows RFC 6570 with verified erratum 6937
(apostrophes are permitted in literals). Invalid syntax and reserved, unsupported
operators fail explicitly. Expansion supports the defined operators, Unicode,
percent-encoded variable names, prefix modifiers, and exploded lists and maps.
Missing and JSON null values are undefined; false remains a defined scalar.
Composite values cannot use a prefix modifier. Map ordering is deterministic by
symbolic key; scalar numbers and booleans use their JSON spelling.

Reserved and fragment expansion preserve valid percent triplets. Other expansion
operators encode the percent sign. Prefix lengths count Unicode characters and
avoid splitting percent-encoded UTF-8 characters. Unicode literal text is encoded
to a URI rather than copied as an IRI.

Generated inverse matchers accept only single-variable simple expressions without
modifiers. Repeated variables, adjacent variables, and separators that cannot
unambiguously separate simple expansions require an explicit matcher. Captured
values contain only unreserved characters or valid percent triplets and must
decode as UTF-8. Returned values are strings; an application needing domain values
or composite inverses supplies its own matcher. Overlap between generated matchers
is checked as described below; custom matcher languages remain unknown.

Resource declarations validate template syntax and variable bindings even with an
explicit matcher. Literal declaration errors carry source locations; computed
URI expressions are checked during construction. URI remappings in views must
preserve the template variable set. The independent URI Template corpus is pinned
under @tt{vendor/uri-template-tests}, with provenance in @tt{vendor/LOCK.json};
@tt{scripts/fetch-inputs.py uri-template-tests} explicitly refreshes that pinned
input. Runtime and compilation perform no network fetch.

@section{Resource route overlap checks}

Interfaces reject overlapping generated URI matchers before serving or recovering
work. This includes fixed resources overlapping templates, differently named
variables describing the same route, and intersections created by mounts or URI
remappings. The error includes a URI accepted by both routes. Locally known
literal resource declarations receive the same check during expansion, with the
error attached to the conflicting URI declaration.

@tt{uri-matchers-overlap} in @tt{mcp/uri-template} returns a witness string for
intersecting generated matchers, false for disjoint generated matchers, or
@tt{'unknown} when either matcher is a custom procedure. The search models both
simple expansion syntax and UTF-8 validity. Its @tt{#:max-states} keyword defaults
to 10,000; exceeding the limit raises an error instead of claiming disjointness.
Custom matchers are never invoked during this analysis. Runtime dispatch retains
its ambiguity check for custom procedures whose accepted URI sets are unknown.

@section{Replacing a task after manual recovery}

A failed task remains failed after its underlying workflow is repaired. For a task
that failed with a recorded uncertain manual effect, inspect its workflow and use
@tt{recover-workflow!} to record an observed outcome or authorize retry. Then call
@tt{retry-runtime-task!} with the runtime, failed task ID, @tt{#:principal}, and
@tt{#:capabilities}. This explicit local API creates a new task for the repaired
workflow. It adds no protocol method and performs no automatic retry of an
uncertain mutation. An abandoned workflow cannot be resumed this way.

The runtime resolves the original mounted operation and adapters, checks task and
operation authorization before allocation and again in the worker, and requires
Tasks plus any declared input capability. Expired, foreign, or incompatible
workflow state is rejected. The replacement uses the existing workflow checkpoints
and effect keys and does not extend the original expiry. Current capabilities are
persisted for subsequent worker recovery.

Replacement creation and its journal links commit together. Repeating the API for
the same failed task retrieves the same replacement handle, including while that
replacement is working or after reopening storage. The old task result and revision
are unchanged. If a replacement itself fails with another uncertain manual effect,
repair that execution and explicitly request replacement of its new failed ID.

The lower-level @tt{retry-recovered-task!} API in @tt{mcp/tasks} accepts a workflow,
store, failed task ID, and owner key, with adapter, custodian, and authorization
callbacks. The authorization callback raises an exception to deny execution.
Applications using that API directly supply their own authorization;
@tt{retry-runtime-task!} applies runtime policy. Only failures carrying the recorded
recovery metadata are eligible; old development records are not inferred from an
error message.

Process-termination tests cover repair before allocation, a committed replacement
before worker execution, an interrupted replacement effect, and terminal completion.
Restart preserves committed handles and outcomes. An interrupted manual effect
fails for explicit recovery without invoking the adapter again; repairing that
replacement creates a third task while both failed task results remain unchanged.
These tests do not establish the complete crash/concurrency matrix for every
workflow, input, and storage transition.

@section{Binding queries for extension authors}

@tt{mcp/extension} supplies expansion-time binding queries. Import it with
@racket[(require (for-syntax mcp/extension))] alongside the transformer libraries
used by an extension. The functions must be called during syntax expansion;
ordinary runtime calls fail. At higher phases, shift this import with the
transformer's other dependencies.

@tt{(lookup-mcp-binding identifier #:space 'value)} returns an immutable
@tt{mcp-binding-info} value or @racket[#f] for an unknown or ordinary host binding.
The optional space is @tt{'value} or @tt{'effect}; effect queries do not confuse
an adapter name with a same-spelled host variable. Queries use binding predicates
and lexical metadata, without evaluating application expressions or compiling a
reference to discover its value.

The information has three fields, with corresponding @tt{mcp-binding-info-kind},
@tt{mcp-binding-info-name}, and @tt{mcp-binding-info-arguments} accessors:
@itemlist[
 @item{@tt{kind}: @tt{schema}, @tt{operation}, @tt{resource}, @tt{prompt},
       @tt{workflow-value}, or @tt{effect}. Tools and workflows share operation.}
 @item{@tt{name}: the original static resource/prompt name, otherwise @racket[#f].}
 @item{@tt{arguments}: a resource/prompt's argument-name symbols in declaration
       order, otherwise @racket[#f]. An empty list means a known zero-argument
       declaration; false means the information is unavailable.}]

@tt{(require-mcp-binding identifier kinds #:space 'value #:context syntax)}
returns the same information when its kind occurs in the nonempty @tt{kinds}
list. Otherwise it raises a syntax error attached to the identifier within the
supplied context, which defaults to that identifier. Extension authors should pass
the complete source form as context. These information values do not create
bindings and contain no compiler representations. Emit the documented declaration
and workflow forms to introduce bindings and retain their normal compiler checks.

The separate @tt{examples/extensions/resource-link-tool.rkt} extension demonstrates
this API: it requires a resource binding, derives a tool description from the
original resource name, and emits an ordinary tool containing a resource link.
Its generated reference still receives core arity checks and interface mapping.
This API does not prove the presence of dynamically composed targets or infer
references hidden in arbitrary Racket computation.

During workflow-stage extension expansion, binding queries also recognize the
workflow arguments and values introduced by preceding checkpoints, input stages,
effects and workflow @racket[let] bindings. Visibility follows the current branch
and lexical block: future values, sibling-branch values and values from a finished
block are unavailable. A pending workflow value shadows a same-named outer schema
or operation for these queries. Ordinary host bindings retain their own behavior.
The compiler exposes this context only while expanding the stage; it does not
register identifiers globally or evaluate value expressions to discover metadata.

Effect-space queries follow lexical stage order as well. A @racket[perform]
introduces its adapter identifier in the effect space for its input expression
and subsequent stages of the same block. Earlier stages, sibling branches and
code after a completed inner block cannot see an adapter introduced only there.
Adapters inherited from an enclosing sequence remain visible across joins.
These rules apply both to workflow extension queries and to expression macros
inside handlers; adapters are not hoisted over the whole workflow. Value-space
bindings with the same spelling remain separate in generated stage environments.
An ordinary host @racket[let] retains Racket lexical shadowing, including for
binding queries in its body. Extension-generated adapters
preserve their scopes, and an unresolved forward query is a source error.

@tt{examples/extensions/checkpoint-copy.rkt} demonstrates the query in a separately
implemented workflow extension. @tt{(checkpoint-copy [saved String] name)} requires
@tt{name} to be an available workflow value and emits a normal checked checkpoint.
Nested extensions and renamed imports retain their scopes. Caller-supplied output
binders are normalized as binding positions so later stages can refer to them;
macro-introduced private identifiers keep their hygiene.

@section{Declarations at shifted phases}

The SDK uses a locally patched syntax-spec-v3 dependency, based on upstream commit
@tt{4ae36610804b58e8f023574bfdcba1b5ae4f7bcd}. The original dependency loses a module
scope when compiling references to declarations created inside
@racket[begin-for-syntax]. The patch preserves the declaration's lexical context
for module-level generated temporaries. Internal bindings keep the original
temporary generation behavior; preserving every internal scope causes ambiguous
bindings in an upstream command-line DSL test.

The patch also constructs persistent identifier tables at the binding phase
corresponding to the compiler module instance. Comparing all identifiers at phase
zero can merge distinct same-spelled local arguments at higher phases, such as
the @tt{id} arguments of unrelated resource and prompt declarations.

@tt{scripts/prepare-syntax-spec.py} verifies the unchanged vendored snapshot and
prepares the patched dependency at @tt{.cache/patched-dependencies/syntax-spec-v3}.
The reference-compiler patch attaches each delayed default directly to its
binding-class transformer, while retaining thread-local scoped overrides. A class first visited in
one worker must remain usable when another worker or the main thread accesses
its exported binding. Defaults previously stored only in a parameter could be
lost across that boundary. Defaults now travel with lexical bindings, without
registration in a mutable table. The promise preserves forward references and
evaluates a default only when it is first used. Scoped overrides take precedence.

The patch has local version @tt{0.1.0.2}, required by the SDK package. Preparation
performs no network access or package installation. The generated
@tt{MCP-PATCH.json} records the upstream commit and original/patched compiler and
binding-table, reference-compiler and binding-generator hashes. See the README for isolated installation and update commands.

@tt{dev/check-phase-references.rkt} tests declarations and ordinary references at
phases 0, 1 and 2 in both MCP and a minimal syntax-spec language that imports no
MCP code. MCP cases include schemas, shapes, tools, resources, prompts, workflows,
same-spelled arguments and host shadowing. Every case runs in a bounded child
process; any failure exits nonzero.
@tt{tests/phases.rkt} includes this probe in routine native verification. Existing
tests also cover shifted imports and declaration metadata. This evidence does
not establish every combination of phases, extensions and dynamic composition.

@section{Interface resource-reference maps}

@tt{make-interface} accepts @tt{#:references}, a hash from tool, resource, or prompt
source descriptors to lists of resource descriptors they reference.
@tt{interface-resource-references} returns the normalized immutable map. Sources
must belong to the interface. Each target must resolve to exactly one published
resource with the same declaration identity; matching a wire name or URI alone
cannot satisfy the reference. Duplicate targets are removed.

Mounts combine these maps. Views remap surviving source descriptors and resolve
their target identities against the transformed resources. Removing a referenced
resource while retaining its source fails during interface construction, before
handlers run. Removing both source and target is allowed. Multiple mounted URI
views of the same referenced identity are rejected as ambiguous. Cyclic references
are allowed because links can be cyclic; recursive embedding retains its own
runtime cycle checks.

The ordinary @tt{resource-ref} constructor checks its resource descriptor, argument
list, exact arity, and each argument's schema through the same path as applying a
resource declaration. Neither form reads the resource. References constructed in
ordinary helpers or from runtime data still resolve against the active interface:
missing and multiply mounted identities raise errors. Dynamic links and embeddings
never select a mount merely because it occurs first in the resource list.

For example, after defining a tool @tt{open-document} and resource @tt{document},
construct their interface with @tt{#:references (hasheq open-document (list document))}.
A view excluding @tt{document} then fails while @tt{open-document} remains exposed.
The map survives @tt{#lang mcp} mounts and runtime validation.

Ordinary @tt{tool}, @tt{resource}, and @tt{prompt} handlers additionally collect
lexically bound resource references through syntax-spec's host-expression API.
This includes references introduced by macros and imported through renamed
bindings. Quoted names and shadowing host bindings do not create dependencies.
The generated procedure carries a private thunk that resolves resource descriptors
when the interface is built; discovery does not execute handlers. Explicit maps
and collected references combine, so an explicit map cannot erase a known edge.

Collection is conservative across branches and nested lambdas in the handler
syntax. It does not inspect separately defined Racket helper procedures or infer
references created from arbitrary runtime data. Supply explicit references for
those relationships. Generated workflow-stage procedures use the same collection
boundary. The workflow descriptor contributes references from every stage,
including branches that may not execute, to its enclosing tool, resource, or
prompt. Reading those references does not open storage, run a stage, or request
input. Ordinary data-API workflows can declare relationships through the explicit
interface map.

Manifest declaration entries include @tt{resource-references}, containing the
original resource names and source locations, and @tt{reference-analysis} set to
@tt{lexical-handler-syntax}. Imported aliases retain the declaration's original
name. Repeated targets are deduplicated and sorted. Missing origin metadata is
explicitly marked unknown. These fields describe references visible in handler
and workflow-stage syntax; they do not prove that separately defined helpers or
dynamic interface expressions introduce no additional references.

Each local resource has a @tt{local-id}. A reference's @tt{local-target} is that
identifier when lexical binding resolves to a resource in this manifest, and
@racket[#f] otherwise. These identifiers are local to this generated manifest;
they are not wire names or stable identifiers across builds. Imported resources
remain external unless their declaration origins resolve to a resource supplied
by a statically known mount; names and source files alone do not establish this.
Generated bindings need no source location to establish a local target.

References also record @tt{binding-provider}: the defining module's file or
symbol identity, submodule path, and binding phase. Re-export aliases retain the
original provider. This distinguishes same-name resources in different submodules
of one file without relying on source positions or generated binding names.
Unavailable module-binding information is explicitly @racket[#f]. These are
static declaration identities, not executable compatibility fingerprints.

Resource origins and references also retain an opaque string @tt{binding-name} from
the module binding. Together with the provider, this distinguishes hygienic
declarations even when their public names and diagnostic locations coincide.
Cross-module resolution uses that binding pair, not source hints. Missing keys
leave a reference unresolved. These compiler names are not public wire names or
stable build identifiers. Diffs ignore their incidental spelling for resolved
public targets; a changed unresolved external binding requires review.
String encoding preserves manifest write/read round trips when Racket uses
uninterned symbols internally for module bindings.

Prompt declarations also carry local IDs and binding origins. A completion's
@tt{prompt-reference} records its lexical prompt target using the same provider,
binding-name and local-target fields. Mounted views resolve it to the prompt's
published name. Diffs normalize incidental IDs and binding names once that target
is resolved; unresolved references require review.

The independent manifest submodule retains @tt{manifest-exclusions} for resources and prompts
explicitly removed by static views. Exclusions survive fragment re-exports.
A local handler referencing an excluded resource receives an expansion error
when no other static mount supplies it and no dynamic mount could supply it.
Multiple known mounts of one referenced binding are ambiguous and also receive
an expansion error. Exclusion is not a permanent ban: another mount can supply
the declaration. Runtime interface checks still arbitrate computed compositions.

The compiler emits the manifest after declaration right-hand sides expand, using
Racket's module-lifting API. The resulting submodule uses @tt{racket/base} and
quoted data only. Reading it does not instantiate the application or its imported
resource providers. Compiling source still executes trusted transformers.

The exported @tt{mcp-interface} binding carries private compiler metadata while
its expression value remains the interface descriptor, including through
@racket[dynamic-require]. Renamed imports and re-exports preserve this metadata.
A module-level @racket[mount] reads only the provider's independent generated
manifest. It includes tools, workflows, resources, prompts and completions, with
fresh local identities for mounted resources. Local handler references can resolve
to those resources through their recorded binding origins.

Static composition recognizes imported interface bindings, @racket[mount-interfaces]
applications, and @racket[view] applications with literal inclusion, exclusion,
renaming, namespaces and URI maps. The literal grammar includes quoted data,
literal hashes, and binding-checked @racket[list], @racket[hash], @racket[hasheq]
and @racket[hasheqv] constructors over literals. It does not evaluate host helpers.
Views retain declared policy expressions in @tt{composition-policies}; dynamic
policy values remain marked unknown. Duplicate known published identities,
overlapping generated URI routes and view removal of an internally referenced
resource receive expansion errors.

Computed interface values, dynamic surface transformations, and mounts inside
host expression contexts are explicit @tt{mount} entries with @tt{known?} set to
@racket[#f], source locations and the unevaluated expression. Their presence does
not assert that their declarations are installed. Documentation and diagrams
display these unknown mounts; diffs require review rather than classifying their
unknown contents as established additions or removals. Runtime interface checks
still apply to dynamically constructed compositions.

Workflow manifest entries also record @tt{client-capabilities}, with @tt{required}
and @tt{optional} objects using the protocol capability names and an @tt{analysis}
value of @tt{declared-workflow-stages}. Input stages require elicitation;
@tt{#:execution task} requires the Tasks extension; @tt{task-optional} records it
as optional because MRTR execution remains available. Task execution modes add
@tt{task-workers} to @tt{runtime-requirements}. The checked execution identifier is
known grammar data, so it does not by itself mark metadata dynamic.

These fields describe the local declared workflow stages, including branches,
and the runtime's capability preflight for those stages. They do not infer hidden
input requests in arbitrary Racket helpers, upstream adapters, or dynamically
composed interfaces. They are client requirements, not server discovery output.
Generated Markdown documentation includes these requirements without evaluating
handlers or input-request expressions. Manifest diffs classify a newly required
elicitation or Tasks capability as a breaking contract change when both entries
contain this analysis. Missing analysis in an older manifest requires review; it
does not establish that the capability was previously unnecessary.

@section{Interface and workflow diagrams}

@tt{raco mcp diagram module.rkt} emits a Mermaid flowchart from the static manifest.
@tt{manifest->mermaid}, exported by @tt{mcp/cli}, accepts an already read manifest
and returns the same text. Neither operation runs application handlers.

The diagram shows declarations, dotted resource-reference and prompt-completion
edges, workflow entry
points, sequential stage transitions, numbered branch alternatives, explicit
joins, and effect adapters labelled with their policy. Completion stages have no
implicit outgoing transition. Imported resources outside the local manifest are
labelled external or unresolved. Unresolved prompt targets receive the same
explicit treatment. Generated manifests use lexical local targets;
older manifests lacking these fields use source/name hints. Explicit external
targets never fall back to those hints. Ambiguous matches remain explicit.

All node identifiers are generated. Declaration and stage names are escaped as
quoted labels using Mermaid decimal entities. The diagram does not execute
callbacks, render HTML supplied by declarations, or infer additional edges from
separately defined helpers or dynamic composition expressions.

@section{Generated interface documentation}

@tt{raco mcp docs module.rkt} generates Markdown from the static manifest.
@tt{manifest->markdown}, exported by @tt{mcp/cli}, accepts an already read manifest
and optional @tt{#:title} and @tt{#:examples} arguments. The result includes known descriptions and metadata,
argument requirements/defaults/codecs, input/output and reusable schemas, completion
targets, resource references, workflow stages, adapter policies, and runtime
requirements. Schema examples remain present in the emitted schema JSON.

Dynamic descriptions, schemas, and other expressions are identified as dynamic
and displayed without evaluation. Reading the manifest does not instantiate the
application. Names and source references use code spans; descriptions are escaped
as text; schema code fences expand when necessary to preserve literal backticks.
Generated documentation describes what the static manifest establishes, including
its documented limits on helper analysis and dynamic composition.

The manifest submodule separately exports @tt{manifest-examples}, a list of
locally authored @tt{scenario} source records in declaration order. Each record
contains @tt{name}, @tt{code}, and source coordinates. Renamed and macro-generated
scenario forms use the same compiler collector. These records contain printed
syntax; collecting or reading them does not evaluate configuration expressions,
start process scenarios, or execute assertions. They do not enter the published
interface declaration list or change wire-compatibility reports.

@tt{read-manifest-examples} from @tt{mcp/cli} reads this export without
instantiating the parent application. Older manifest modules without the export
return an empty list. Pass its result as @tt{#:examples} to
@tt{manifest->markdown}; @tt{raco mcp docs} does this automatically. The resulting
section labels the scenarios as source examples, not test-run results. Code fences
are extended when source contains backticks. These local examples are not rewritten
through mounted views: run the source module's scenarios to exercise their actual
configuration. Compiling the module still executes trusted Racket transformers.

@section{Static compatibility reports}

@tt{raco mcp diff before.rkt after.rkt} and @tt{manifest-diff} compare published
static declarations. Reports are ordered deterministically and include changed
and unchanged fields. Removed declarations are @tt{breaking-removal}; newly
required arguments and changed known published resource URIs/templates are
@tt{breaking-contract-change}. Other static changes require review. New
declarations are reported as added. Duplicate published identities are errors.

Known resource identities use their URI or URI template, not their display name.
Different URIs may share a name; changing a name while retaining the URI requires
review rather than reporting a removal. Unmatched resource entries with a unique
name on each side are associated for a URI-replacement report only when both
surfaces have fully known resource identities and no dynamic mounts. Otherwise known
URI additions and removals are reported separately. Unknown resource URIs require
review, including unmatched known URIs that an unknown counterpart could retain.
Dynamic mounts also prevent definite addition/removal claims for declarations
whose counterpart could be supplied by the unresolved mount.

Completion identities combine the target's kind and published identity with the
argument name. Prompt targets use their published name; resource targets resolve
lexical references to their published URI/template, including through mounts and
URI remappings. Equal display names therefore do not merge distinct resource or
prompt completions. A completion targeting a resource excluded by a static view
receives the same expansion diagnostic as other references to that resource.
Older manifests without resolved resource-completion references require review;
display names alone do not establish their identity.

Runtime interface construction resolves resource completion targets by declaration
identity. A completion declared outside a mounted view can therefore target that
view's unique transformed resource. Missing and ambiguous identities are errors;
an unrelated resource with the same URI does not satisfy the reference. Duplicate
target/argument pairs are checked after resolution, both during static composition
and by @racket[make-interface].
@racket[make-runtime] retains normalized completion targets when given a raw
interface descriptor. If the supplied interface is already normalized, its
descriptor identity is preserved.
The same resolution applies to prompt completions across renamed and nested
views. Views retain a private prompt declaration identity while preserving the
public five-argument @racket[prompt-descriptor] constructor. A separately
constructed prompt with the same name does not satisfy a reference to the
original declaration. Required scopes remain attached to the published target.

Compiler-owned source positions and incidental local-ID renumbering do not affect
comparison. Local target IDs resolve to declaration identities before comparison;
retargeting and local/external changes require review. Duplicate local IDs and
dangling local targets are errors. Resource-reference
origins retain their source and binding-provider identities so distinct providers
with the same name are not collapsed. Older manifests without provider information
cannot establish submodule distinctions. Schema properties named @tt{source} or @tt{line} remain
application data and still participate in comparison. Ordinary tools and workflow
tools share one published identity for comparison.

Every entry states that handler behavior was not compared. An unchanged static
manifest does not establish handler equivalence or schema subsumption. Workflow
reports identify known incompatible version changes, added/removed workflows, and
stage changes requiring review. Identical stage metadata reports
@tt{not-established-from-manifest}; compatible executable code still requires
the runtime's independent version/fingerprint checks.

@section{Boolean tool schemas and omission}

An omitted @tt{#:output} declares no structured-output contract. Explicit
@tt{#:output #t} (including @tt{Any}) declares an unrestricted structured value;
@tt{#:output #f} declares an impossible successful structured value. The latter
still permits an explicit execution-error result. @tt{make-tool} uses @tt{missing}
as its optional-keyword sentinel, so applications can explicitly pass
@tt{#:output missing} to omit the contract.

The pinned MCP schema requires schema objects on the wire. Constructors lower
@tt{#t} to an empty schema object and @tt{#f} to an object whose @tt{not} keyword
contains an empty schema. The descriptor's @tt{output-schema} field remains
@tt{#f} when absent; present boolean declarations are stored in normalized object
form. Raw @tt{tool-descriptor} values must already use this representation.

An omitted @tt{#:input-schema} derives the ordinary argument schema. Explicit
boolean input schemas are normalized over JSON objects: @tt{#t} accepts any
object, and @tt{#f} accepts none. Supplied object schemas must declare
@tt{type: "object"} at the root, as MCP requires. Interface construction also
checks normalized schema fields and header annotations for raw descriptors.

@section{Raised values at failure boundaries}

Racket handlers may raise values other than exceptions. @tt{dispatch-message}
converts non-break failures into internal-error responses, preserving explicit
MCP errors. It does not serialize the raised value into the protocol response.
Task workers record such failures as terminal failures; uncertain manual effects
retain their recovery-required state. Retrying a failed task does not execute
that effect again.

Notification and post-commit outbox callback failures remain deferred delivery
failures. Diagnostics do not invoke custom printers on non-exception payloads.
Break exceptions retain their existing control-flow meaning.

@tt{store-transaction} preserves the original raised value after rollback.
Nested calls in the same thread share that transaction; child threads do not
inherit ownership merely by inheriting parameters.

@section[#:tag "transaction-ownership"]{Transaction ownership and terminated workers}

Stores opened by @tt{open-memory-store} and @tt{open-sqlite-store} supervise
transactions under a store-owned custodian. The supervisor owns the database's
managed transaction and the store semaphore. Application code runs in its original
thread and parameterization, including transactional effect adapters.

Normal callback completion commits before returning its values. Exceptions,
arbitrary raised values, breaks, continuation escapes, and prompt aborts roll
back. If a worker is killed or its request custodian shuts down, the supervisor
observes its death and rolls back before releasing the store lock. Cleanup is
asynchronous after forced termination; acquiring the next store transaction waits
for it. Cancellation while waiting for the lock does not require the preceding
transaction to finish. Applications cannot commit the managed transaction early.

The supervisor lives as long as the store's custodian; callers must open shared
stores outside individual request custodians. @tt{close-store!} disconnects the
store and shuts down its supervisors. Directly constructed @tt{state-store}
values use the calling custodian and do not provide the factory stores' independent
supervisor lifetime. Store opening, simultaneous store shutdown, and process
termination are separate lifecycle boundaries; the worker-termination tests do
not establish every possible crash/commit race.

@section[#:tag "runtime-clock"]{Controlling logical time}

@tt{mcp/clock}, also exported by @tt{mcp}, provides a shared logical clock for
reproducible interactions. @tt{current-mcp-clock} is a parameter whose value is
a zero-argument procedure returning finite real Unix milliseconds. Its default
is Racket's wall clock. @tt{mcp-current-milliseconds} reads that clock;
@tt{mcp-current-seconds} floors it to an exact integer Unix second.

@tt{make-runtime} accepts @tt{#:clock}; the default captures the current clock
procedure when the runtime is constructed. @tt{runtime-clock} returns it.
Dispatch and HTTP authentication use that runtime's clock even when the caller
has a different parameterization. Detached task workers inherit it. Runtime task
recovery, explicit repaired-task retries, and change publication also select it.
Default caches and pagination use the same source. Explicit @tt{#:cache} and
@tt{#:cursor-clock} arguments retain their independently supplied clocks.

Workflow and rendering expiry, task timestamps and expiry, journal timestamps,
outbox retention, and principal expiry checks use logical time. Standalone
storage/workflow/task and OAuth helper calls use the current parameter, unless
an existing explicit @tt{#:clock} argument overrides that helper. Those older
helper arguments continue to use seconds; cache and runtime clocks use milliseconds.
A raw @tt{runtime} constructor does not capture a clock: use @tt{make-runtime}
when clock ownership is required.

@racketblock[
(define clock (make-manual-clock #:seconds 100))
(define rt (make-runtime an-interface #:clock clock))
(manual-clock-advance! clock 1/2)
]

@tt{make-manual-clock} returns a callable, thread-safe clock initially at the
supplied finite Unix seconds (default zero). @tt{manual-clock-advance!} adds
finite nonnegative seconds and returns the new millisecond value. Exact rational
inputs retain exactness; negative advances, infinities, and NaN are rejected.
The clock is application configuration, not serialized workflow state. Supply
the intended clock explicitly when reopening a store or restarting a runtime.

The executable @tt{examples/clock-scenario.rkt} demonstrates authored cache
expiry with @tt{raco mcp scenario examples/clock-scenario.rkt}. Advancing logical
time does not sleep or schedule threads. Transport deadlines, cleanup grace
periods, and task-worker polling still use real alarm events. The complete
scenario fault language and deterministic scheduling controls remain unfinished.

@section[#:tag "scenario-runs"]{Scenario execution and submodules}

@tt{raco mcp scenario module.rkt} runs the module's @tt{test} submodule in a fresh
module registry and under a dedicated custodian. It reports Racket test-log
results and fails when a test reports failure, even when RackUnit catches the
assertion exception. Unhandled failures and a missing test submodule also fail
the command. Resources owned by the run are shut down on return or exception.
A prior run's results and instantiated modules do not carry into the next run.

The equivalent @tt{run-scenarios} function is provided by @tt{mcp/scenario} and
@tt{mcp/cli}. It accepts a module file path and returns a pair of failed and total
test counts on success; reported test failures raise an exception. Frameworks
using Racket's @tt{raco/testing} log participate in the same accounting. Successful
code with no logged tests returns @tt{(0 . 0)}; the runner does not manufacture
assertions. This tooling uses the declared native @tt{compiler-lib} dependency.

Within @tt{#lang mcp}, @tt{module+} groups and @tt{module*} with @tt{#f} retain
ordinary Racket module bodies. They inherit the parent interface binding instead
of generating another interface and executable entry point. Repeated groups,
imports, definitions and macro-generated groups compose normally. Declarations
inside these ordinary submodules remain ordinary descriptor values and are not
published in the parent's interface. To define an independent MCP child language,
use an explicit language, for example @tt{(module* child mcp/lang ...)}.

The clock example now uses an ordinary @tt{module+ test} RackUnit import followed
by its authored @tt{scenario}. The existing scenario body remains Racket test
code. The complete transport-selectable fault-injection language remains an
implementation gate; this runner does not claim to supply it.

@section[#:tag "scenario-sessions"]{Configured interaction scenarios}

A configured scenario binds a session for its Racket body:
@racketblock[
(scenario (greeting session)
  #:interface mcp-interface
  #:transport 'stdio
  #:clock (make-manual-clock #:seconds 100)
  #:principal "reader"
  (define reply
    (scenario-call session "tools/call"
                   (hasheq 'name "greet" 'arguments (hasheq 'name "Ada"))))
  (check-equal? (hash-ref (hash-ref reply 'result) 'content)
                (list (text-content "Hello, Ada"))))
]

The @tt{#:interface} expression is required. Optional clauses follow this order:
@tt{#:transport}, @tt{#:clock}, @tt{#:principal}, @tt{#:adapters},
@tt{#:capabilities}, @tt{#:state}, @tt{#:authorize}, @tt{#:timeout},
@tt{#:sse?}. Configuration expressions run once, in that order, when the test
submodule executes. They do not run when the application's interface descriptors
are constructed. The session binder has ordinary lexical Racket scope in the
body. Missing interface clauses, malformed binders and repeated/out-of-order
clauses fail expansion. The older @tt{(scenario name body ...)} form remains valid.

@tt{call-with-scenario-session}, exported by @tt{mcp} and @tt{mcp/scenario}, is
the equivalent procedure. It takes an interface and a one-argument callback plus
the same optional keywords. It returns the callback's values and closes the
session's transport, runtime workers and store on exit. A retained session rejects
later calls. The defaults are local dispatch, a manual clock at Unix zero,
principal @tt{"scenario"}, empty adapters/capabilities, memory storage, an
allowing authorization callback, a five-second real request timeout, and a
preference for quick HTTP JSON responses. @tt{#:state} supplies an explicit SQLite path. Reusing that path
in another session permits continuation tests across runtime/store reopenings;
it does not simulate killing a separate process.

@tt{scenario-request} takes the same arguments as @tt{scenario-call} and returns
an SDK @tt{request-handle} immediately. Import @tt{mcp/stdio} for the common
handle accessors and @tt{request-cancel!}. Synchronizing the handle returns its
JSON-RPC outcome or exception value; @tt{scenario-call} waits and raises exception
values. The handle's notification channel supports authored progress and
subscription assertions while other requests are running. Request deadlines use
real elapsed time, independently of the scenario clock. Both call forms accept
@tt{#:timeout}: a positive finite number of seconds, or @tt{#f} to disable the
request deadline. Ordinary requests default to the session timeout; subscription
listeners default to @tt{#f}, matching the SDK clients. HTTP still bounds response
header acquisition by the session timeout. An explicitly bounded subscription
can test timeout behavior without changing other requests. Cancellation retains the
first terminal outcome, signals cooperative cancellation, and bounds worker
cleanup. Session exit cancels outstanding requests before destroying their event
machinery, so escaped handles remain synchronizable. Local dispatch uses a bounded
256-message notification queue; overflow terminates the request with
@tt{exn:fail:notification-overflow}. Wire transports retain their own SDK limits.

@tt{scenario-call} takes the session, a method string and an optional JSON params
object. @tt{#:capabilities} can override the session's capabilities for that call.
Each call gets a fresh request ID and returns its JSON-RPC outcome. Local calls
round-trip request data through JSON and use @tt{dispatch-message}. Stdio calls
use the actual SDK client/server over bounded pipes; HTTP uses a loopback server
and the actual SDK client. @tt{#:sse? #t} selects HTTP SSE responses. Transport
errors retain their native exception types; for example, HTTP authorization
challenges may raise an HTTP authorization exception. Failed or uncertain calls
are never automatically replayed.

@tt{scenario-interact} accepts session, method and params, requires explicit
@tt{#:elicit} and @tt{#:navigate} callbacks, and delegates MRTR/Tasks interaction
to @tt{run-interaction}. Optional @tt{#:max-rounds} and @tt{#:wait} retain that
runner's policy. Logical clock advancement does not replace real task scheduling.
Session accessors expose its runtime, store, clock, transport and principal for
authored assertions and fixtures.

The HTTP session installs the supplied principal through a testing authentication
adapter; it exercises runtime authorization rather than a hosted OAuth flow.
@tt{serve-stdio} now also accepts @tt{#:principal}, defaulting to @tt{'local}, so
the same principal/policy can be tested through all three paths. HTTP scenario
keep-alives are at most one second and at most half the request timeout.

Call timeouts and session teardown are tested with uncooperative handlers.
Longer HTTP requests now switch from the JSON preference to SSE, allowing stream
closure to cancel work before session teardown. The regression probe at
@tt{dev/check-http-json-disconnect.rkt} passes for this adaptive behavior.
Asynchronous requests, notification assertions and explicit cancellation are
available through the session API. Explicit transport loss is available through the controls below; actual process
restarts and the complete fault grammar remain unfinished.


@section[#:tag "http-adaptive"]{Adaptive HTTP responses and worker lifetime}

With @tt{#:sse? #f}, @tt{make-http-handler} and @tt{serve-http} prefer JSON for
requests that finish within @tt{#:stream-after} seconds (default @tt{0.05}). If
that window expires, or a request emits a notification, the response becomes a
request-scoped SSE stream. The same worker and event queue continue execution;
the handler is not restarted. Explicit @tt{#:sse? #t}, progress requests and
subscriptions continue to select SSE immediately. @tt{#:stream-after} must be a
finite nonnegative number; @tt{#:sse? #f} is not a promise to return only JSON.
MCP clients must support both response types.

An initial SSE comment flushes headers promptly. Later keep-alive comments expose
stream closure during otherwise quiet computation. Detection latency depends on
the configured keep-alive interval and network buffering. Once stream delivery
fails, cleanup signals cooperative cancellation, waits up to 200 milliseconds,
and shuts down the request custodian. A TCP input half-close is not treated as
cancellation: the client may still be waiting to receive the response.

@tt{serve-http} associates request workers with the web server's connection
custodian, which differs from its longer-lived servlet custodian. A delivery
scope also cleans up requests if response headers fail before the body writer
runs. Runtime-owned task workers retain their independent ownership. Integrators
using @tt{make-http-handler} directly must supply an appropriate enclosing
custodian and response-delivery lifecycle; @tt{serve-http} installs that adapter.

Quick JSON results use the same encoded bytes that passed the response-size
limit. Both paths apply the configured size limit to each encoded JSON-RPC message.
This change satisfies the previously recorded disconnect probe through adaptive
SSE; it does not interpret socket input EOF as proof that a client cannot receive
JSON, or introduce informational HTTP heartbeat responses.

When @tt{serve-http} selects an ephemeral port with @tt{#:port 0}, its default
Origin policy uses the configured host and the actual listener port obtained
from the connection. It does not derive authority from the request's Host header.
An explicit @tt{#:origins} list replaces this default, including for ephemeral
listeners.

@section[#:tag "view-adapter-restrictions"]{Restricting named effect adapters}

@tt{view} accepts @tt{#:allow-adapters}, either @tt{#f} (no additional restriction)
or a list of adapter symbols. An empty list denies all named adapters. Nested
views intersect their lists; a later view or adapter replacement cannot widen an
earlier restriction. Mounts, renaming, URI remapping and the generated
@tt{mcp-interface} retain each declaration's policy.

The equivalent data API is @tt{make-interface #:adapter-restrictions}, an immutable
snapshot of a hash mapping included declaration descriptors to allowlists or
@tt{#f}. @tt{interface-adapter-restrictions} returns this map. Invalid adapter names
and policies referring to absent declarations fail construction.

Runtime dispatch supplies a guarded adapter map. Looking up a forbidden adapter
raises MCP error @tt{-32001}, including when that name is not configured. Declared
workflow adapters are looked up before checkpoints and task creation; denied task
updates do not persist input. Task recovery uses the recovering runtime's policy.
Nested dispatch intersects the parent restriction with the child's policy, even
when the child uses another runtime. This also covers dynamically constructed
workflows using the supplied adapter map.

These restrictions govern named SDK adapters. Arbitrary host Racket code remains
trusted and can have effects outside that API; this is not a Racket sandbox or a
claim that a tool is read-only. Tool annotations do not establish effect safety.
@tt{interface-effect-summary} returns JSON-compatible records with declaration
kind/name, declared workflow adapters, the adapter policy and optional allowlist.
Every record explicitly reports @tt{hostEffects} as @tt{"unknown"}. An empty list
of declared adapters does not establish host-code purity. This summary uses
descriptors and does not execute handlers.

@section[#:tag "external-change-reconciliation"]{Reconciling external committed changes}

@tt{mcp/external-changes} supplies @tt{make-external-change-source},
@tt{external-change}, @tt{external-change-page}, @tt{reconcile-external-changes!},
@tt{external-change-cursor}, and @tt{reconciliation-result}. These bindings are
also available from @tt{mcp}. Source construction takes a stable name, an explicit
version, a reader procedure and optional @tt{#:initial-cursor} (JSON null by
default). Construction performs no feed reads or storage operations.

The reader accepts the saved JSON cursor and requested event limit. It returns an
@tt{external-change-page} containing a list of @tt{external-change} values and the
next JSON cursor. Each event has a nonempty string ID, a nonempty principal key
string, and a JSON list of dependency keys. For a verified principal, use
@racket[principal-key] from @racketmodname[mcp/authorization] to retain both issuer
and subject identity; a bare subject name does not identify that authorization
context. The reader observes an authoritative
committed-change feed or an application-owned reconciliation scan. The application
must connect that feed to its commits; the SDK cannot infer changes omitted from
the feed. A cursor must not skip committed events. Reader I/O and its deadlines
are application responsibilities. The SDK never calls a mutation callback.

Each @tt{reconcile-external-changes!} call reads one page outside the state-store
transaction. It then atomically records new event identities, creates their
pending change-outbox entries and advances the cursor. Empty dependency lists
record the event without producing an outbox entry. Repeated identical events are
deduplicated; reusing an ID with another principal or keys rejects the whole page.
IDs are scoped to the logical source, including across principals. A change that
affects multiple principals therefore needs distinct stable event IDs for those
principal-specific reports.

Concurrent readers compare the stored revision before committing. A stale page
returns a @tt{reconciliation-result} with status @tt{'superseded}, zero recorded
events and the current cursor. Other successful calls return status
@tt{'recorded}, the number of new event identities and the resulting cursor.
There is no automatic refetch loop. A reader exception, malformed page or storage
failure leaves the prior cursor and outbox intact. The source configuration may
already have been recorded before the failed read.

@tt{#:max-events} defaults to 1000. @tt{#:max-bytes} bounds the accepted encoded
page and defaults to the storage-supported 1 MiB; it can be lowered, but cannot
exceed that storage limit. These limits validate reader output and do not limit
the reader's own allocations or network buffering. Event receipts and source
cursors are retained without automatic pruning, preserving deduplication across
restarts. Source version or initial-cursor changes under an existing name are
rejected rather than resetting progress. @tt{external-change-cursor} inspects the
saved cursor, or returns the configured initial value without creating state.

Use @tt{runtime-reconcile-changes!} to reconcile through a configured runtime and
then drain its pending outbox through normal cache invalidation and notification
policy. The low-level API only records changes. Delivery remains at least once:
interruption after publication but before acknowledgement can deliver the same
outbox identity again. Delivery callbacks must tolerate this. Reconciliation does
not repeat the application mutation, and it does not promise exactly-once remote
delivery. The runtime applies its logical clock and principal-specific policy;
this API does not introduce a global wildcard invalidation principal.

@tt{examples/external-changes.rkt} is an executable adapter for a small append-only
JSON feed published by atomic replacement. Supply its source name, feed path and
explicit SDK SQLite state path. It reads the feed and prints pending outbox
deliveries; requiring the module does neither. A production database adapter can
use the same API with its own durable change log and paginated reader.

@section[#:tag "captured-loading"]{Loading interfaces with executable identity}

@defmodule[mcp/loader #:use-sources (mcp/loader)]

@defproc[(load-interface [path (or/c path-string? module-path?)]
                         [#:runtime-build-id runtime-build-id string?])
         interface-descriptor?]{
Loads the module's @racket[mcp-interface] in a fresh namespace, shares the current
SDK's descriptor types and runtime parameters, and seals captured workflows to
an executable identity. Available from @tt{mcp} and @tt{mcp/loader}. Filesystem
paths are resolved against the caller's current directory. Fragments without a
server declaration can be loaded, but serving still requires a server.

The nonempty @tt{runtime-build-id} is the caller's immutable identity for the
already-loaded SDK, its language/compiler dependencies, and the running Racket
executable/distribution, including predefined modules. Use the same identity only
for the same runtime build. The SDK cannot verify that this supplied identifier
truthfully describes already-loaded code. It is never used as a substitute for
uncaptured application code. A package version reused across changed development
builds does not meet this contract.

Application module code is captured as it is evaluated, including helpers loaded
during instantiation. Application declarations without observed code or a retained
producer identity cause an error; Racket's
compiled-module cache can require using a fresh loading process. No resume-time
file hashing substitutes for the loaded executable. User-written definitions and
imports execute with normal module-instantiation semantics. Constructing the
interface does not itself start a transport, open workflow storage, or invoke
handlers.

A workflow retains its captured namespace. Ordinary dynamic imports during its
execution must refer to modules already loaded and included in the sealed build.
Prepare those imports during application loading. Changing a captured helper or
the runtime build ID rejects incompatible saved execution. Replacing a source
file after loading does not replace the code retained by that loaded workflow.
Fresh and unreadable symbols are rejected as module names in captured loading:
their printed names can alias distinct identities, including predefined modules.
Use file modules or stable interned module/submodule names. A public registration
API for portable identities of these reflective modules is not implemented yet.
This is not a sandbox for trusted Racket code that deliberately changes its own
resolver or namespace.
}

The serving command opts into this loader with an explicit runtime identity:
@verbatim{raco mcp --runtime-build-id MY-IMMUTABLE-RUNTIME-BUILD --state state.sqlite serve application.rkt}

The @tt{mcp/command} entry point starts in Racket's kernel language and installs
observation before loading ordinary SDK libraries. Direct file execution and
@tt{racket -l mcp/command} use this cold entry. The @tt{raco mcp} launcher starts
that entry in a fresh Racket process from the same installation, so libraries
already loaded by @tt{raco} do not escape observation in the serving process.
Arguments are passed without a shell; standard streams and the exit status are
forwarded. Interrupting the launcher terminates its owned child. For supervisors
that forcibly terminate process trees, include the child serving process; an
uncatchable parent-only termination does not run Racket custodian cleanup.
Importing the kernel command alone does not load the ordinary SDK.
Kernel observations transfer to the SDK collector by module registry, and retained
loader hooks forward later declarations until the command scope closes. For
SDK dependencies evaluated under observation, captured loading uses the actual
compiled module code in its original module registry instead of the supplied
identity. The explicit identity remains required for dependencies loaded before
observation, including predefined runtime modules. Importing the SDK first or
calling @tt{mcp/cli} directly does not retroactively observe those modules.

Use the same compiled SDK build when restarting durable execution. Fresh source
compilation can produce different compiled code even without source edits; this
is conservatively treated as a different executable. Rebuilds are not promised
compatible merely because their source text or package version is unchanged.
An SDK code change captured by this entry point invalidates saved execution even
when the caller supplies the same runtime identity.

Captured fingerprints now use the @tt{mcp-executable/3} format and include the
execution namespace's base phase. Identical code executed at different phases
therefore has distinct build identities. On Linux, when
@tt{/proc/self/exe} is readable, the fingerprint includes a cached SHA-256 identity
of the running executable image. Its original pathname is never used as a
substitute: that pathname may have been replaced since process startup. Unreadable
procfs evidence, including stale backing-file handles, is recorded as unavailable.
Other platforms currently have no automatic executable-image evidence. This
component does not identify shared libraries, host-injected libraries, or the
whole runtime distribution, so the explicit runtime build ID remains required.
Earlier captured fingerprints are conservatively incompatible with this format;
resume them using their compatible SDK/runtime build.

The returned descriptor works with ordinary @tt{make-runtime}, local dispatch,
stdio and HTTP APIs. Captured tool, resource and prompt workflows use the same
validation and authorization paths. A changed build currently reaches stdio
clients through the runtime's ordinary internal-error channel; local workflow
calls retain the recovery diagnostic.

Executable capture uses retained producer identities when available, including
for dependencies declared before its scope began. Otherwise it hashes code that
it actually observed being evaluated. A preloaded dependency without either kind
of evidence remains unresolved; a replacement file is never used to identify it.
The same identity selection applies to observed SDK bootstrap code. The explicit
runtime identity is still required for the remaining unobserved runtime baseline.

The language reader starts with kernel-only bootstrap observation before loading
its ordinary reader and observer dependencies. After handoff, retained loader
callbacks continue forwarding to the installed observer. Reinstalling a seed
cannot replace newer code already observed in the same module registry. The
language runtime also installs an idempotent observer before subsequent
application dependencies load. Source and compiled imports retain the
actual evaluated module code, including after the corresponding files change.
The observer preserves caller evaluator behavior and scopes records by module
registry. Code loaded before the observer remains explicitly unknown. This is
private capture infrastructure; it does not yet seal a complete executable
identity for the default serving path.

The compiler hook also retains a producer identity in the language metadata of
module declarations it compiles. It requests saveable module code, compiles once,
hashes the artifact with an unfilled metadata cell, and fills that cell before
returning. The identity-information provider itself uses only the kernel language, so a
startup query for a stamped kernel module does not load ordinary libraries before
its observation boundary. The original language-information provider remains
available through delegation. Identity reflection reads an already declared module without loading
files or running its handlers; replacing or deleting its files cannot change the
retained identity. This is trusted compiler metadata, not a signature or a proof
of equivalence across different builds. Any transformation after identity creation
requires a new identity. These per-module identities are not yet a complete
default-path durable build fingerprint.

Automatic runtime provenance is not asserted for ordinary loading. Applications
can use the declared identity contract below without a capture boundary.
Inspection commands continue to use the generated manifest rather than this
instantiating loader.

@subsection{Declared identities for ordinary loading}

@defmodule[mcp/build]
@defparam[current-build-identity identity (or/c #f non-empty-string?) #:value #f]{
The application/runtime identity for descriptors constructed and durable operations
executed in this scope. The SDK retains an immutable copy. This is an application
assertion, not observed provenance, a code signature, or proof that initialization
succeeded. The application must change it whenever its application code, imported
helpers, adapters, codecs, SDK, Racket runtime, or native dependencies change in a
way that can affect resumed execution. Use an immutable deployment identifier or
a digest of the application's controlled build inputs.
}
@defproc[(call-with-build-identity [identity non-empty-string?] [thunk (-> any)]) any]{
Calls @racket[thunk] with the declared identity. Workflows created by ordinary
@tt{make-workflow}, macro declarations, or factories retain it after the scope ends.
Normal Racket loading and instantiation semantics are preserved; this function
neither reloads modules nor seals an observed dependency capture. A failed module
initialization propagates normally and does not produce a successful interface.
}

@tt{make-workflow} accepts @tt{#:build-id}, defaulting to the current parameter.
@tt{make-runtime} accepts the same keyword and retains it for dispatch, durable
worker execution and startup recovery, including descriptors constructed before
that runtime exists. @tt{runtime-build-identity} returns the retained identity.
If both workflow and runtime declare an identity, they must agree; a conflict
fails before workflow execution. Constructor validation rejects empty strings and
values other than strings or @racket[#f].

The identity participates in workflow fingerprints, plain-handler parent rendering
state, and local/upstream continuation and task bindings. Changed identities reject
incompatible resumes; task input updates reject them before persisting input.
Read-only retrieval of recorded native task results and cancellation do not run the
old program. Existing terminal task states remain immutable. Direct low-level
workflow execution or upstream recovery APIs must run under the matching declared identity
scope; runtime recovery functions supply that scope automatically.

@verbatim{(define rt (make-runtime mcp-interface #:store store #:build-id "my-application/42"))
racket application.rkt --build-id my-application/42 --state state.sqlite
raco mcp --build-id my-application/42 --state state.sqlite serve application.rkt}

@tt{--build-id} works with ordinary source and compiled module loading, including
the generated direct entry point. It does not instantiate the application twice.
@tt{serve-interface} accepts the corresponding @tt{#:build-id} keyword.
@tt{--runtime-build-id} remains the separate captured-loader contract above;
applications can use both contracts, in which case both identities constrain
compatibility. Without either contract, local program/version/codec/adapter checks
remain available but do not establish compatibility of imported helpers or the
runtime. Reusing a declared ID after changing those dependencies violates the
application's contract; the SDK cannot detect that misdeclaration automatically.

@subsection{Recognizing interface descriptors}

@defmodule[mcp/descriptor #:use-sources (mcp/descriptor)]
@defproc[(interface-descriptor? [value any/c]) boolean?]{
Recognizes an SDK interface descriptor, including descriptors returned by
@racket[load-interface]. The predicate does not instantiate application modules
or invoke handlers.
}

@defproc[(interface-requires-state? [interface interface-descriptor?]) boolean?]{
Reports whether the published tools, resources, or prompts contain a workflow or
an upstream bridge requiring a state store. It inspects descriptor metadata
without invoking handlers or credential callbacks. Mounting, renaming, and
rebuilding descriptors preserve bridge requirements; removing all stateful
declarations with a view removes the requirement. Ordinary application I/O is
not inferred from Racket procedures. The serving command uses this predicate to
require an explicit state-file path before acquiring runtime resources.
}

@section{Generated server commands}

@defmodule[mcp/cli]
@defproc[(serve-interface-command [interface interface-descriptor?]) void?]{
Parses the current command-line arguments and serves an already-instantiated
interface. Generated @tt{#lang mcp} main submodules call this function. It accepts
@tt{--state}, @tt{--transport}, @tt{--port} and @tt{--build-id}; options use the same parser as the
@tt{raco mcp} command. Unexpected positional arguments are rejected.

For example, @tt{racket examples/approval.rkt --state approval.sqlite} runs the
durable example over stdio. The state path remains mandatory for durable
workflows and upstream bridges. Application definitions and imports are not instantiated a second
time by the command handler.

Serving owns its SQLite connection and runtime/transport workers from startup
through shutdown. If runtime construction fails, startup is interrupted, or
stdio reaches EOF, those resources are released without shutting down the
caller's custodian. Runtime workers stop before the state store closes. Cleanup
attempts each owned resource and preserves an existing failure or escape; a
cleanup failure on ordinary return is raised to the caller.

Captured loading cannot be retroactively applied to an already-instantiated
module. Supplying @tt{--runtime-build-id} here produces a diagnostic directing the
caller to @tt{raco mcp --runtime-build-id ID [options] serve MODULE}; it does not
silently ignore the identity or reload application definitions. Use @tt{--build-id}
for the declared application/runtime identity contract with this direct entry point.
}


@section[#:tag "notification-discovery"]{Discovery of notification support}

For each installed tool, prompt or resource category, discovery advertises
@tt{listChanged: true}. Resources also advertise @tt{subscribe: true}. These
flags describe the runtime's installed subscription broker and publication path;
a category with no declarations remains absent. Applications can publish list
changes through @tt{publish-change!} from @tt{mcp/subscription}, using the runtime's
subscription hub. Resource dependency changes use the existing freshness path.
The flags do not make external application mutations observable automatically.

The independent Go fixtures in @tt{dev/subscription-server.rkt} and
@tt{dev/interop/subscriptions.go} exercise automatic listener creation on discovery,
acknowledgement filters, tagged changes, server-requested closure, continued calls
and fresh connections over stdio and HTTP. They supplement the scenario tests
that directly assert the subscription completion result.


@subsection{Subscription filter authorization}

Known list-change filter fields must be booleans; @tt{resourceSubscriptions}
must be an array of strings. Invalid known fields produce @tt{-32602} before
registration, including fields for an unavailable category. Unsupported categories
remain omitted from the accepted filter, and duplicate resource URIs are collapsed.

Before acknowledgement, each accepted list-change filter requires authorization
for its corresponding list operation. Each accepted resource URI requires
@tt{resources/read} authorization, including scopes preserved by URI remapping and
views. Tasks retain their operation and ownership checks. A denied target rejects
the subscription with @tt{-32001}; no acknowledgement or listener is installed.
These checks resolve declaration policy without running resource readers.

Before each subsequent event, the runtime rechecks the target operation's policy
and principal expiry; task events also recheck ownership. Events denied by current
policy are suppressed. Restoring permission permits later eligible events on the
same listener; suppressed events are not replayed. This applies even when an
application publishes directly through the runtime's subscription hub. The generic
standalone hub has no application authorization policy of its own.


Subscription scope preflight includes the union of scopes for the listen operation
and its supported targets: configured list-operation scopes, resource-read scopes
(including declaration/view requirements), and each stored task's operation scopes.
HTTP checks this union before starting SSE. A token lacking those scopes receives
HTTP 403 with an @tt{insufficient_scope} challenge, the required scope list and
protected-resource metadata URL, without a subscription acknowledgement. Local
and stdio dispatch use the same scope calculation. Authorization callbacks and
task ownership are still checked separately; knowing the required scopes does not
grant access to another principal's task.


@section[#:tag "scenario-disconnect"]{Transport loss in scenarios}

@tt{scenario-disconnect!} closes the current session's stdio pipes or HTTP
listener and active connections. Outstanding requests and subscriptions observe
the SDK client's transport-failure outcome, distinct from a locally requested
cancellation. Calls issued while disconnected fail immediately.
@tt{scenario-session-connected?} reports whether the session can issue requests.

@tt{scenario-reconnect!} starts a fresh transport against the same runtime, store,
clock, principal and adapters. It does not replay requests, reopen subscriptions,
or change an already completed handle. Request IDs may restart on the fresh
connection. Applications explicitly re-listen and refresh as needed. Repeated
disconnect/reconnect calls in the corresponding state are harmless; either control
rejects a session that has exited. Local sessions reject disconnect because they
have no wire connection.

Runtime-owned task workers survive this fault and can be polled after reconnect.
This control stops the session's server transport, not the application runtime or
process; it does not simulate SQLite reopen, process termination, packet loss or
loss of one selected HTTP request while keeping others connected. Session exit
still shuts down the runtime and its owned store normally. The executable
@tt{examples/disconnect-scenario.rkt} runs with
@tt{raco mcp scenario examples/disconnect-scenario.rkt}.

A stdio output failure is now reported once by the serving call. It interrupts a
reader blocked on input, gives request workers bounded cleanup, and preserves the
original raised value. Background workers do not retry writes to the failed
output or emit uncaught secondary diagnostics. Scenario-injected pipe loss captures
that expected serving failure; clients still observe actual EOF.


@section[#:tag "scenario-process"]{Process-backed scenarios}

@tt{mcp/scenario-process}, @tt{mcp/scenario} and @tt{mcp} export
@tt{call-with-scenario-process}. Its first argument is a nonempty command list
(executable followed by path/string arguments); its second is a procedure receiving
an opaque process-scenario value. No shell is inserted. The child fixture owns
its interface, adapters, principal, clock and storage configuration. Those Racket
values are not serialized from the parent. An explicit SQLite path in the command
lets a restarted fixture resume the same application state.

The equivalent language form is:
@verbatim{
(scenario (restart child)
  #:command (list (find-executable-path "racket") application "--state" state-file)
  #:capabilities (hasheq 'elicitation (hasheq))
  ...)
}
Configuration expressions run in the test submodule, once in declaration order.
The optional clauses, in order, are @tt{#:transport}, @tt{#:capabilities},
@tt{#:timeout}, @tt{#:shutdown-timeout}, @tt{#:stderr-limit}, @tt{#:directory}, and
@tt{#:environment}. The function accepts the same keywords. Defaults are stdio,
empty capabilities, a five-second request/startup timeout, two seconds per cleanup
phase, a 65,536-byte stderr tail, the current directory and a copied environment.
The executable, arguments, directory and environment are retained across restarts.

@tt{scenario-process-request} returns the SDK's event-compatible request handle;
@tt{scenario-process-call} waits and raises exception outcomes. Both accept method,
optional params, @tt{#:capabilities} and @tt{#:timeout}. Subscription deadlines
default to @tt{#f}; other requests use the configured timeout. A buffered native
reply is drained before classifying process loss. If the client cannot supply a
terminal outcome after process exit, @tt{exn:fail:scenario-process-loss} carries
the observed PID and exit status. Cancellation uses the native request handle.

@tt{scenario-process-kill!} hard-kills and reaps the child. Repeating it is harmless.
@tt{scenario-process-restart!} kills a running generation and starts a fresh child;
it does not replay requests. Old handles retain their terminal outcomes.
@tt{scenario-process-running?}, @tt{scenario-process-pid}, and
@tt{scenario-process-status} expose observed process state.
@tt{scenario-process-stderr} returns the bounded raw-byte tail for the current or
most recently stopped generation. Capture it before restarting if it must be kept.
Scope exit first closes stdin, then uses a bounded wait and forced termination if
necessary. Pending handles settle before client workers are destroyed. Requests
share one drain deadline; stderr has its own bounded drain phase.

For @tt{#:transport 'http}, the child must print a loopback HTTP URL with an explicit
port as its first stdout line (under 8,192 bytes), then serve that endpoint. The
harness bounds startup, drains subsequent stdout, and captures stderr separately.
The transport does not automatically send discovery or replay an uncertain call.
The command runs as a normal child process, with the supplied directory/environment.

@tt{examples/process-restart-scenario.rkt} demonstrates an actual hard restart at
an MRTR input boundary. The process controls complement in-process session controls;
they do not automatically serialize deterministic adapters or inject process-local
clock changes. Authored child fixtures supply those facilities explicitly.
