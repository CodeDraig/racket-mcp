# Dynamic OAuth registration

`mcp/oauth-registration` provides explicit RFC 7591 registration for the MCP
2026-07-28 authorization-code flow. Registration sends one request. It never
follows a redirect or retries an uncertain registration.

```racket
(require mcp/oauth-registration)

;; authorization-metadata comes from the existing verified discovery API.
(define result
  (register-oauth-client!
   authorization-metadata
   (hasheq 'client_name "My Racket client"
           'application_type "native"
           'redirect_uris '("http://127.0.0.1:3080/callback")
           'grant_types '("authorization_code" "refresh_token")
           'response_types '("code")
           'token_endpoint_auth_method "none")))

(define issuer (oauth-registration-result-issuer result))
(define registered-metadata (oauth-registration-result-metadata result))
```

## Request API

`(register-oauth-client! authorization-metadata requested-metadata ...)` accepts
JSON objects and returns an opaque `oauth-registration-result` with these accessors:

- `oauth-registration-result?`
- `oauth-registration-result-issuer`
- `oauth-registration-result-metadata`

The result's printed representation hides its metadata, which may include a
client secret. Explicitly reading or printing the metadata exposes those values;
applications must treat it as credential material.

The authorization-server metadata is checked with the existing metadata validator.
Callers must obtain it through trusted discovery and issuer validation. This
function does not discover an issuer or establish trust in caller-supplied URLs.
It sends JSON to that metadata's `registration_endpoint`. HTTPS is required;
`#:allow-loopback-http? #t` explicitly permits HTTP on loopback for local fixtures.

Optional keywords:

| Keyword | Default / behavior |
|---|---|
| `#:initial-access-token` | `#f`; otherwise a Bearer token sent only to the registration endpoint |
| `#:timeout` | 30 seconds; positive finite total request timeout |
| `#:max-response-bytes` | 1,048,576; positive response byte bound |
| `#:max-header-bytes` | 65,536; positive header byte bound |
| `#:allow-loopback-http?` | `#f` |

Supply `application_type` explicitly as `"native"` or `"web"`. Requests must
contain nonempty absolute `redirect_uris`; HTTP callbacks must be loopback.
The supported token authentication methods are `none`, `client_secret_basic`,
and `client_secret_post`. Omission uses RFC 7591's `client_secret_basic` default.
Grant and response defaults are `authorization_code` and `code`. Requested grants
must include `authorization_code`; response types must include `code`.
Server-issued identity and secret fields cannot be supplied in a request.

## Returned metadata and failures

`(validate-oauth-registration-response requested-metadata response-metadata)`
performs the same validation independently of HTTP and returns the validated
JSON object. JSON objects use the SDK's symbol-keyed hash representation. Wire decoding
rejects duplicate keys. Known core metadata fields are type-checked. Unknown extension fields are
retained as JSON data, without asserting extension-specific validity. Embedded
`jwks` receives structural object/key-list checks, not cryptographic validation.

Successful HTTP responses must have status 201 and one JSON content type. The
response must contain a nonempty `client_id`, valid registered callback URIs,
and a supported token authentication method. Secret authentication requires a
secret; a supplied secret requires a nonnegative integer `client_secret_expires_at`
(0 means no expiry). Optional `client_id_issued_at` must also be a nonnegative
integer. Expiry is validated as metadata, not checked against the current clock.

All requested callbacks must be returned, without additional callbacks. Requested
grants and response types must remain available. These are SDK usability checks:
RFC 7591 permits server substitutions, but an unusable registration is rejected
rather than silently adopted. Display metadata may change; unknown extensions
are retained. A supplied software statement must be returned unchanged. There
is no automatic retry with adjusted metadata.

Non-success HTTP responses raise `exn:fail:oauth-http` (exported by
`mcp/oauth-http`), preserving status, headers, and bounded response bytes. This
includes registration errors such as `invalid_redirect_uri` and
`invalid_client_metadata`. The ordinary exception message contains the status,
not the response body. Malformed JSON or incompatible metadata raises an error.
Timeouts, breaks, and all response paths close request-owned resources.

The request API is a low-level operation. Durable registration reuse and opt-in
authorizer integration are described below. Existing conformance scores are unchanged
by these local tests.

## Durable registration reuse

```racket
(require mcp/storage mcp/oauth-registration-store mcp/oauth-registration)
(define store (open-sqlite-store "private-state/credentials.sqlite"))
(define registered
  (ensure-oauth-registration! store authorization-metadata requested-metadata))
;; Use registered metadata with the existing token-authentication API.
(close-store! store)
```

`ensure-oauth-registration!` accepts a state store, freshly discovered and verified
authorization-server metadata, and requested client metadata. It returns an
`oauth-registration-result`, loading an existing registration or issuing and
persisting a new one before returning. It creates a versioned registration table
in the supplied store. Use `open-sqlite-store` with an explicit path for durability;
`open-memory-store` is supported but ephemeral.

The persistence key is the exact issuer identifier plus canonical JSON for the
requested client metadata. Different issuers never share registrations or secrets,
even if their client IDs match. Changing the requested client configuration gets
a separate registration. A changed issuer from discovery gets a new registration;
returning to an earlier issuer may reuse that issuer's still-valid registration.
Changed endpoints under the same issuer do not by themselves invalidate a client
registration. No previous issuer's credentials are passed to the registration
adapter. The caller remains responsible for verified discovery on each selection.

Secret expiry is checked against Unix seconds: positive expiry at or before now
triggers a fresh registration, while 0 means no expiry. A newly returned expired
secret is rejected. Public registrations without secrets do not expire through
this field. The API does not revoke old registrations or implement RFC 7592
registration-management updates. Stored responses are revalidated before reuse.

| Keyword | Default / behavior |
|---|---|
| `#:clock` | `mcp-current-seconds`; a procedure returning nonnegative integer Unix seconds |
| `#:allow-loopback-http?` | `#f`; explicit local-fixture policy |
| `#:register` | Native `register-oauth-client!` adapter; accepts AS metadata and requested metadata and returns a registration result |
| `#:retry-uncertain?` | `#f`; explicit permission to attempt another registration after an uncertain attempt |

Use `#:register` to configure request timeouts, bounds, or issuer-specific initial
access tokens. The adapter must return a validated result for the selected issuer;
a foreign result is rejected. This registration store does not select pre-registration or CIMD and does not
persist access tokens. The authorizer integration below handles selection and
token authentication; its existing load/save callbacks handle token persistence.

An intent is committed before calling the authorization server. Threads and
processes coordinate through the existing storage worker locks; competing calls
receive an in-progress error. Network work runs outside a database transaction.
Calling this API inside `store-transaction` is rejected. Failure or process death
between intent and the durable result leaves an uncertain registration. Subsequent
calls fail without making another request. After assessing the possible orphaned
registration, `#:retry-uncertain? #t` authorizes a new attempt; it cannot override a
live worker lock. It does not guarantee exactly-once registration. Failed result
persistence does not return an apparently durable registration to the caller.

**Storage contains plaintext credential material**, including issued secrets.
Use an application-private directory and appropriate filesystem permissions for
the SQLite file, journals and backups. The SDK does not encrypt this database or
provide an OS credential vault. Explicit metadata access can expose secrets;
the opaque result's default printed representation does not.

References: [RFC 7591](https://datatracker.ietf.org/doc/html/rfc7591),
[MCP client registration](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/client-registration).

## Authorizer integration

```racket
(require mcp/oauth mcp/storage)
(define store (open-sqlite-store "private-state/credentials.sqlite"))
(define authorizer
  (make-oauth-authorizer
   #:resource "https://service.example/mcp"
   #:redirect-uri "http://127.0.0.1:3080/callback"
   #:browse application-browser-callback
   #:registration-store store
   #:registration-metadata
   (hasheq 'application_type "native"
           'redirect_uris '("http://127.0.0.1:3080/callback")
           'client_name "My Racket client"
           'token_endpoint_auth_method "none")))
(define credential (authorize-resource! authorizer))
;; Keep store open while the authorizer is in use; close it at application shutdown.
```

Providing both `#:registration-store` and `#:registration-metadata` opts into DCR.
Existing callers are unchanged. Selection prefers issuer-matching pre-registration,
then a configured CIMD document when supported. Only otherwise does it use the
store and the discovered registration endpoint. Without that endpoint, the
existing `#:request-registration` callback remains the manual fallback.

The authorizer installs the **returned** client ID, authentication method and
secret into native code exchange and refresh. Supported methods are
`client_secret_basic`, `client_secret_post`, and `none`; the result must also be
supported by authorization-server metadata (whose default is Basic). Secret
material is never added to browser URLs. Returned `none` uses only the client ID.
A newly selected issuer obtains its own registration and token-cache identity.

The optional `#:register` callback accepts authorization-server and requested
client metadata and returns a registration result; use it to configure registration
HTTP bounds or issuer-specific initial access credentials. It requires a store and
registration metadata. Dynamic registration cannot be combined with a custom
`#:exchange`, which owns authentication itself. A static authentication entry for
an issuer that needs DCR is rejected before sending a registration request.

The store checks expiry on selection. The authorizer checks again immediately
before sending a code or refresh token, because browser interaction may outlast
the secret. Expiry at that point fails without a token request or automatic
mid-flow registration. Existing explicit reauthorization and uncertain-token
exchange policies apply. Registration uncertainty is recovered explicitly through
`ensure-oauth-registration!` with `#:retry-uncertain? #t`; ordinary authorization
never silently repeats an uncertain registration.

Application `#:load`/`#:save` token callbacks retain their existing
issuer/client-ID/resource keys. The registration store is separately owned by the
application. This integration does not change independent conformance scores
without running the corresponding scenarios.
