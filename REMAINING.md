# Remaining release work

Mutable current state for the approved seven-milestone MCP 2026-07-28 release.
Remove a row when its completion evidence is recorded in IMPLEMENTATION.md;
replace a partial row with only its unmet portion. Do not reopen completed work
without a regression or a dependency of a remaining requirement. Historical
"remains open" statements in IMPLEMENTATION.md are not additional work items.

| ID | Concrete unmet work | Evidence needed to remove this row |
|---|---|---|
| PLATFORM | Obtain final-source Racket 9.2/9.3 native macOS and Windows verification. | Native builds/tests/package/docs run successfully. GitHub run 34268172343 terminates with startup_failure and zero jobs; startup cause is not established. |
| RELEASE | Refresh Linux/package and affected interoperability checks after declared-build integration, compare two source archives, and finalize the original-plan evidence map. | Prior full Linux 9.2 run passed 6,256 tests, schema/regex and Scribble; installed checks passed both versions. Record final-source checks and archive hashes. PLATFORM stays separate. |

Latest baseline: the authored-example compiler changes passed 6,238 native tests,
1,301 schema core cases, 86 regex cases and Scribble on Linux Racket 9.3. Twenty
subsequently integrated language/durability cases passed on both 9.2 and 9.3. This does not reopen
previously demonstrated behavior. Optional format assertions remain outside the
approved annotation-default requirement; regex support is assessed against the
promised tested compatibility profile, not an invented full-JavaScript mandate.
