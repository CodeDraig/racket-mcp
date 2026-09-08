# Supported OAuth acceptance closure

The independent offline-access-scope fixture advertises CIMD, so it is applicable
without adding excluded DCR behavior. run.py serves the SDK-generated client
metadata document at a temporary HTTPS loopback address. The harness trusts only
this extra temporary certificate through NODE_EXTRA_CA_CERTS; certificate
verification is not disabled and no global trust/configuration changes occur.
The temporary private key is deleted. The development client now accepts the
metadata URL through MCP_CONFORMANCE_CLIENT_METADATA_URL.

The harness exited zero and its final console summary reports 12 passing checks,
zero failures/warnings. It fetched /client-metadata.json and reported SUCCESS for
sep-2207-client-metadata-grant-types after inspecting refresh_token in grant_types.
The client chooses not to request optional offline_access; that is INFO, not a
failure. The generated metadata is retained independently.

Harness artifact discrepancy: checks.json is saved before scenario shutdown.
The CIMD fetch/check occurs during shutdown, so the saved JSON contains the early
INFO "not inspected" entry (11 SUCCESS plus request-trace/other INFO entries),
while harness.log contains the later successful check and final 12/12 summary.
Both are retained; the JSON has not been rewritten to manufacture a pass.

## Native behavior and applicable fixture mapping

| Supported requirement | Existing inspected coverage |
|---|---|
| PKCE, state/issuer/resource validation; server verified claims and challenges | tests/authorization.rkt, tests/http-authorization.rkt, tests/authenticate.rkt |
| Protected-resource and authorization-server discovery, OIDC metadata provenance | tests/authorization-discovery.rkt, tests/oauth-metadata.rkt |
| Pre-registration and hosted CIMD document construction/validation | tests/client-registration.rkt; oauth-client-authentication-20260908/pre-registration-checks.json and cimd-checks.json |
| Scope precedence, refresh, concurrent credential use, issuer migration, persistence and uncertain exchange | tests/oauth-flow.rkt, tests/oauth-tokens.rkt |
| Bounded native token HTTP; Basic/Post/None, issuer/endpoint credential isolation | tests/oauth-http.rkt, tests/oauth-client-authentication.rkt |
| HTTP authorization integration, stale challenge and token installation | tests/oauth-http-client.rkt |
| Production HTTPS default and explicit isolated fixture loopback policy | tests/oauth-authorizer-policy.rkt |
| Resource/metadata issuer rejection before registration | oauth-client-authentication-20260908/resource-mismatch-checks.json and metadata-issuer-mismatch-checks.json |
| Fetchable CIMD refresh grant metadata | This artifact's HTTPS access record, generated document and terminal harness log |

The existing native test files passed in the ed75ea8 full Linux 9.3 run and are
unchanged. The four prior applicable independent scenarios total 29 successful
checks; the new scenario adds the previously missing fetchable metadata evidence.

The other frozen auth fixture flows (metadata-default/var1/var2/var3, scope-*,
token-endpoint-auth-*, offline-access-not-supported, authorization-server-migration,
and iss-* excluding metadata-issuer-mismatch) do not advertise CIMD or provide
issuer-scoped pre-registration context. Their mock AS exposes /register by
default and requires DCR for a complete flow. The migration fixture specifically
requires a new registration at AS2. These complete fixtures are excluded from this
release, not treated as passing proof of discovery/scope/issuer behavior; the
native tests above cover those implemented behaviors. The applicable early
metadata-rejection scenarios run before this registration boundary.

Other optional auth extensions, a hosted authorization server, hosted application
metadata and browser/credential persistence implementations remain outside the
approved release. OAUTH is removed from REMAINING.md; final-source independent
conformance remains under CONFORMANCE rather than reopening supported auth work.
