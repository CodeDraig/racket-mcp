# Reproducible registration fixture repair

Prepared using scripts/prepare-conformance.py, with 279 pinned files verified.
Only the AS registration response differs; patch and manifest are retained here.
All 20 OAuth scenarios ran: 17 clean passes, one warning-only scenario
(scope-step-up), two failures (metadata-var2 and iss-not-advertised).
No malformed-registration rejection remains. These are locally patched fixture
results, not unmodified conformance credit.

Preparation tests: 6 pass. Native registration tests: 67 pass. SDK source and
validation are unchanged. See CONFORMANCE-FIXTURE.md for the design note and
reproduction commands. commands.json, exits.json, summary.json and raw results
record each scenario independently. No hosted Actions were used.
