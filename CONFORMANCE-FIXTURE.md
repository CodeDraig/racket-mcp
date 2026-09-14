# Registration fixture correction

## Brittle commitment

The pinned conformance AS builds a registration response independently of its
requested metadata and advertised authentication methods. It issues a secret
without the RFC 7591-required expiry field, drops grant metadata, and can omit the
registered method (defaulting to Basic) while advertising only public-client
`none`. A strict SDK rejects this before the scenario reaches token exchange.
Changing SDK validation to accommodate that response would spread a fixture defect
into runtime credential handling.

## Expected change

The AS fixture must return complete usable registration metadata: expiry 0 for
its non-expiring test secrets, registered grant and response types, and the
selected authentication method. Explicit scenario method overrides remain
controlling; otherwise the requested supported method is used, falling back to
the AS's first advertised method. SDK validation and scenario assertions remain
unchanged. Scope is the pinned fixture, not all possible authorization servers.

## Smallest localized extension seam

`scripts/prepare-conformance.py` verifies the conformance commit and all locked
source hashes, then repairs one response-construction block in a separate copy.
This follows the existing syntax-spec preparation pattern. Upstream vendor data
remains immutable. A source refresh requires reviewing the correction instead of
silently carrying it onto a different implementation.

The organizing computation stays: discover AS, register client, authorize,
exchange token, evaluate the unchanged scenario checks.

## Selected mechanism

Layering: an explicit development preparation layer corrects the fixture's
response representation before harness execution. It reads requested metadata,
issued credentials and advertised methods, and owns only response completion.
It does not change scenario selection, validation, scoring, registration lifecycle,
or the SDK. There is no runtime fallback that suppresses malformed responses.
Unknown source revisions, hash drift and ambiguous patch matches fail preparation.

## Containment evidence

Six preparation tests check exact localized output, preserved input and unrelated
files, rejected hash drift, rejected unknown pins, ambiguous/missing patch blocks,
invalid dependency paths and refusal to overwrite a prepared/user directory.
The prepared manifest verifies 279 upstream files and records the sole changed
file's before/after hashes. Sixty-seven native registration tests still pass,
including rejection of malformed secret expiry and metadata.

The 20-scenario prepared run has 17 clean passes, one scope warning and two
unrelated failures. No registration-metadata error remains. The unchanged pinned
run and its failures are retained in oauth-all-scenarios-20260908. Removing the
preparation layer restores that byte-identical upstream fixture; no SDK mode or
validation toggle needs undoing. Patched results do not count as unmodified
upstream conformance credit.

## Tradeoffs

The correction adds no SDK runtime overhead or retained application state. It
copies the 279 pinned harness files for development and optionally links an
existing node_modules directory. It adds one preparation command, a manifest and
an explicit patch to review at upstream refresh. It avoids a general-purpose
patch/plugin framework. The existing development dependencies are not installed
or independently verified by this script. The three previously recorded OAuth
behavior differences remain outside this correction.

## Focused experiment or test

```sh
python tests/prepare-conformance.py
python scripts/prepare-conformance.py --node-modules /path/to/existing/node_modules
. scripts/racket-env.sh
raco make tests/oauth-registration.rkt
raco test tests/oauth-registration.rkt
.cache/patched-dependencies/conformance/node_modules/.bin/tsx \
  .cache/patched-dependencies/conformance/src/index.ts client \
  --command "racket $PWD/dev/conformance-auth-client.rkt" \
  --scenario auth/token-endpoint-auth-basic --spec-version 2026-07-28 \
  --output-dir .cache/conformance-results
```

Use `--output` to select a fresh preparation directory for another run. Existing
outputs are never overwritten. Without `--node-modules`, preparation still
succeeds but does not attach dependencies. No network or global installation is
performed. These are local corrections, not a published upstream fix.

Evidence, all 20 commands/results and exact source manifests:
`test-artifacts/registration-fixture-repair-20260909`.
