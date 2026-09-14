# OAuth response issuer correction

The MCP 2026-07-28 authorization response table permits an absent `iss` when
`authorization_response_iss_parameter_supported` is false or absent. The SDK now
implements that case while requiring an exact issuer match whenever `iss` is
present and rejecting absence when support is advertised.

## Native verification

On Linux with Racket 9.3, the new `tests/oauth-response-issuer.rkt` regression
failed 4 of 36 cases before the correction and passed all 36 afterward. It covers
metadata true/false/omitted; missing, matching, foreign, malformed, and normalized
issuer variants; state and error checks; and whether token exchange was invoked.

With `PLTUSERHOME="$PWD/.cache/ci/package-home-9.3-current"` and
`PLTCOLLECTS="$PWD:"`, these commands passed:

```sh
raco make tests/oauth*.rkt tests/authorization*.rkt tests/authenticate.rkt \
  tests/client-registration.rkt tests/http-authorization.rkt \
  dev/conformance-auth-client.rkt mcp/scribblings/mcp.scrbl
raco test tests/oauth*.rkt tests/authorization*.rkt tests/authenticate.rkt \
  tests/client-registration.rkt tests/http-authorization.rkt
raco scribble +m --htmls --dest .cache/oauth-response-issuer-20260914/manual \
  mcp/scribblings/mcp.scrbl
git diff --check
```

The broader native run passed 553 checks. Compilation first replaced stale 9.2
compiled modules. The build reports a duplicate `mcp` tool registration from the
existing package links; it does not prevent tests or the manual build.

## Prepared-harness verification

All six issuer scenarios passed: `auth/iss-supported`, `auth/iss-not-advertised`,
`auth/iss-supported-missing`, `auth/iss-wrong-issuer`, `auth/iss-unexpected`, and
`auth/iss-normalized`. No scenario reported failures or warnings. The individual
logs, exact argument vectors, source hashes, and check counts are retained here.

The harness is pinned to `7022d786071e6d868dcd5cf19a8c30db7d811537` and prepared
using `scripts/prepare-conformance.py`. Preparation verified all 279 locked
source files before applying the previously documented registration-fixture
correction. The fixture manifest is retained here. These are prepared-harness
results, not unmodified upstream conformance credit or a new full-suite score.

The initial six runner attempts stopped before scenario execution because the
existing Node dependency tree lacked an Octokit module. An offline `npm ci
--ignore-scripts --no-audit --no-fund` using `.cache/npm` restored 300 packages in
the isolated harness. An initial restoration attempt followed the dependency
symlink and partially cleaned the original cache; that cache was restored from
the successful installation after verifying identical package-lock bytes.
Initial runner and installation logs remain in `.cache/oauth-response-issuer-20260914`.
No global packages were installed and no upstream fixture or validator was changed
for this issuer correction.
