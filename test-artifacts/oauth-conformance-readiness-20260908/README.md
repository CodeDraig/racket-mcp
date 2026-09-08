# OAuth conformance readiness, 2026-09-08

Read-only inspection of the pinned harness found that client auth fixtures use
http://localhost endpoints (helpers/serverLifecycle.ts). The native authorizer
rejects this resource before metadata fetch, as loopback-probe.rkt demonstrates.
The low-level OAuth HTTP adapter has a numeric-loopback option, but authorization
URL validation still requires HTTPS. Running the fixtures needs an explicit test
transport policy that preserves their metadata and the production HTTPS default;
rewriting received issuer values would not establish the required interoperability.

The current dev/conformance-client.rkt does not use the OAuth authorizer at all.
The pinned auth/pre-registration fixture supplies issuer-scoped client_id and
client_secret context and requires client_secret_basic. oauth-registration carries
issuer/client ID/redirect/resource/scopes; the native HTTP adapter has no client-
secret authentication option. Applications can currently replace the exchange
callback. The native configuration and the conformance client integration still
need work. Other auth fixtures cover CIMD, discovery, scope changes, refresh and
issuer validation; optional extension scenarios must be classified against the
release scope instead of indiscriminately claimed as applicable.

This is preparation evidence, not an OAuth conformance run or a claim that native
HTTPS authorization is broken. No harness code or received metadata was changed.
