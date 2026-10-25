# Release-summary evidence — 2026-10-25

This record preserves the focused comparison used to assess the practical value
of recent fixes while accepting the Tasks error-ordering limitation for now.
The acceptance is recorded in [REMAINING.md](../../REMAINING.md). It does not
authorize publication or erase a conformance failure.

The same four test files from commit `4ab93a8` were run against isolated Git source
archives of `d2d2372` and `4ab93a8`, using Linux/Racket CS 9.3. The earlier source
had 23 failures out of 104 tests; the current source passed all 104. Tests cover
numeric responses across replay/restart, retained defaults in embedded workflows,
completion validation, and missing required prompt arguments. This comparison
isolates the subsequent fixes; it does not establish that every recent change
improved behavior or test the ownership fix against its parent.

`results.json` retains the actual command lines, exit statuses, timing, and local
scratch log paths. The same logs are copied into this directory. Input revisions
and test hashes are in `comparison-inputs.json`. To reproduce, extract each
revision into a separate fresh directory, replace only the four named test files
with their bytes from `4ab93a8`, point `PLTCOLLECTS` at that directory (with the
trailing default-path separator), and use Racket 9.3 with the prepared dependency
available in its package home. Run the recorded `raco test` command in each copy.
The original isolated copies remain below `.cache/recent-change-comparison-b_py2l3a`.

Full Linux 9.2/9.3 validation and qualified conformance results are preserved in
[the earlier October 25 record](../public-readiness-20261025/README.md).
Those results predate the release-summary edits. Runtime tests and distribution
builds were not repeated for this documentation-only update. Historical reports,
archive hashes and failed checks have not been rewritten.

Documentation-update checks passed: release totals agree with the recorded JSON
results, relative Markdown links resolve, comparison test hashes still match,
evidence checksums verify, and `git diff --check` is clean.
