# Native OAuth client authentication, 2026-09-08

The native token adapter now supports explicit client_secret_basic,
client_secret_post and none configurations. The authorizer selects configurations
by the discovered issuer, checks the registered client ID and advertised method,
and uses the same adapter for code exchange and refresh. The HTTP adapter binds
credentials to the configured token endpoint; metadata fetches have no client
authentication. Opaque immutable configurations do not print secrets.

An explicit authorizer loopback-HTTP option enables the unmodified upstream
localhost fixtures. Default authorizers still require HTTPS, including when
called inside a fixture authorizer. Client ID Metadata Document URLs always
require HTTPS. Received URLs are not rewritten.

The 89-check focused run exercises actual Basic/Post/None HTTP bodies and headers,
Unicode and reserved-character credential encoding, immutable secret capture,
endpoint and client-ID rejection before sending, cross-issuer credential
isolation, native authenticated refresh, nested policy isolation and invalid
configuration. IPv6 policy is tested with fake callbacks; this run does not claim
an IPv6 network connection.

The pinned unmodified conformance harness at commit
7022d786071e6d868dcd5cf19a8c30db7d811537 passed basic-cimd (12), pre-registration
(12), resource-mismatch (2), and metadata-issuer-mismatch (3), with no failures or
warnings. The mismatch scenarios reach the metadata validation requirement before
rejecting; checks.json records those observations. These are four scenarios, not
the complete OAuth conformance suite. The last two are classified as draft
scenarios by the pinned harness.

The development client uses a fixture browser callback that reads the harness's
immediate redirect, validates its callback address and returns the response to the
SDK. It does not follow arbitrary browser redirects or host application metadata.
Production browser interaction and credential persistence remain application APIs.

The discovery-metadata fixtures require a client-registration check and advertise
DCR without CIMD. The token-endpoint-auth and most issuer/scope fixtures likewise
provide no pre-registration context or CIMD advertisement. Their complete flows
cannot be treated as applicable passing checks for this release, which explicitly
excludes DCR. Native discovery, scope and issuer tests still apply; this limitation
does not excuse defects in those implemented behaviors. Other optional auth
extensions and previous protocol revisions remain outside the approved release.

Commands used the project environment and Racket 9.3, then the pinned harness
`client --command .../racket .../dev/conformance-auth-client.rkt --scenario NAME
--spec-version 2026-07-28 --timeout 60000`. Logs have trailing whitespace trimmed.
The focused Racket 9.2 run passed 238 checks across the new suites and existing
authorization, discovery, registration, flow, HTTP adapter and client integration
suites. All 14 official Go probes, 89 installed-package checks and installed dependency
setup passed. Full Racket 9.3 validation passed 5,881 native checks, 1,301 core
schema cases, 86 optional regex cases, compilation and Scribble. All 279 harness
files match the pinned lock hashes. This artifact is not a release-completion claim.
