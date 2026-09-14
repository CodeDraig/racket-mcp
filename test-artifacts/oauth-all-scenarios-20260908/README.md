# Twenty OAuth conformance scenarios (2026-09-08)

The development conformance client now enables the SDK's dynamic registration
store and native token authentication. It uses ephemeral storage per harness
process; durable reuse/restart behavior is tested separately by the native suite.
The fixture browser remains loopback-only and no hosted CI was used.

All 20 requested scenarios were run twice on Linux Racket 9.2. The first run uses
the pinned, unchanged harness source: **0/20 scored passes**. A separately copied
harness with corrected registration response fields produces **17 clean passes,
1 warning-only scenario, and 2 failures** (18/20 under scenario-tier scoring).
These diagnostic passes are not official unmodified conformance passes.

## Per-scenario results

| Scenario | Unmodified fixture | Registration fixture corrected |
|---|---|---|
| `auth/metadata-default` | FAIL | PASS |
| `auth/metadata-var1` | FAIL | PASS |
| `auth/metadata-var2` | FAIL | FAIL |
| `auth/metadata-var3` | FAIL | PASS |
| `auth/scope-from-www-authenticate` | FAIL | PASS |
| `auth/scope-from-scopes-supported` | FAIL | PASS |
| `auth/scope-omitted-when-undefined` | FAIL | PASS |
| `auth/scope-step-up` | FAIL | PASS with warning |
| `auth/scope-retry-limit` | FAIL | PASS |
| `auth/token-endpoint-auth-basic` | FAIL | PASS |
| `auth/token-endpoint-auth-post` | FAIL | PASS |
| `auth/token-endpoint-auth-none` | FAIL | PASS |
| `auth/offline-access-not-supported` | FAIL | PASS |
| `auth/authorization-server-migration` | FAIL | PASS |
| `auth/iss-supported` | FAIL | PASS |
| `auth/iss-not-advertised` | FAIL | FAIL |
| `auth/iss-supported-missing` | FAIL | PASS |
| `auth/iss-wrong-issuer` | FAIL | PASS |
| `auth/iss-unexpected` | FAIL | PASS |
| `auth/iss-normalized` | FAIL | PASS |

## Findings and limitations

The unmodified AS returns secrets without `client_secret_expires_at` (required
by RFC 7591 section 3.2.1), omits requested grant metadata, and often omits the
registered authentication method while advertising only `none` (the omitted
method defaults to Basic). The SDK rejects these responses. No validator was
weakened. `fixture-correction.patch` supplies expiry 0 for issued secrets, returns
grants/response types, and makes the registered method consistent with AS support.
It changes response data only, not scenario assertions or scoring. The correction
lives in `.cache/conformance-oauth-registration-20260908`; vendored sources and
the original runtime harness are unchanged.

Remaining diagnostic differences:

- `auth/iss-not-advertised`: SDK defect. `finish-authorization` requires `iss`
  unconditionally, rejecting its absence even when support was not advertised.
- `auth/scope-step-up`: SDK warning. Reauthorization uses the new challenged
  scopes without retaining the previously granted scopes. Required checks pass,
  but the CLI exits 1 because of its SHOULD warning.
- `auth/metadata-var2`: unresolved resource-identity interpretation. The harness
  serves root metadata identifying the bare origin, while the requested MCP URL
  ends in `/mcp`. The SDK requires exact resource equality and rejects before AS
  discovery. The upstream harness already lists a known example-client failure
  for this scenario in `src/scenarios/client/auth/index.test.ts`. This diagnostic
  run does not establish which interpretation should change.

## Evidence and reproduction

`run.py` and `commands.json` record the unmodified CLI invocations. The second run
and commands are in `corrected-fixture/`. Each directory contains per-scenario
logs, exit codes and untouched harness `checks.json` output. `summary.json` is
computed by `summarize.py`: at least one SUCCESS and no FAILURE is a scenario
pass; warnings do not fail tier scoring. Exit codes are retained separately.
Expected negative-client exits are judged by harness checks, not mistaken for
scenario failures.

`auth-source-sha256.json` records the original auth source hashes, byte-compared
against vendor/conformance. The complete runtime `src` tree also matches the
vendor copy (the retained existing-harness-overlay.patch is empty).
`sdk-source-sha256.json` identifies the exercised SDK/client sources. The SDK is
commit c1137f3 with the development client wiring as the only code change.

To reproduce the diagnostic copy, copy pinned `src`, `requirements`, package.json
and tsconfig.json to an isolated directory, use the existing pinned development
node_modules, then apply fixture-correction.patch. The SDK runtime remains native
Racket; Node/tsx is the existing independent development harness. Both runners
use the normal harness CLI with spec version 2026-07-28 and a 60-second scenario
timeout. There is no network dependency installation in these runs.

Validation: `raco make dev/conformance-auth-client.rkt`, 40 total scenario
invocations, result-file completeness assertions, source comparisons and
`git diff --check`. The task was to wire and run every scenario; the findings above
are recorded rather than presented as completed protocol fixes.
