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

This API does not install credentials into an authorizer, persist registrations,
or enable automatic DCR fallback. Callers can explicitly use the returned client
ID with the existing registration API and authentication settings with
`oauth-client-authentication`. Integrating registration selection, secret expiry,
and persistence is a separate lifecycle requirement. Existing conformance scores
are unchanged by these local tests.

References: [RFC 7591](https://datatracker.ietf.org/doc/html/rfc7591),
[MCP client registration](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/client-registration).
