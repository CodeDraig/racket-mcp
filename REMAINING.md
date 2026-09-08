# Remaining release work

Mutable current state for the approved seven-milestone MCP 2026-07-28 release.
Remove a row when its completion evidence is recorded in IMPLEMENTATION.md;
replace a partial row with only its unmet portion. Do not reopen completed work
without a regression or a dependency of a remaining requirement. Historical
"remains open" statements in IMPLEMENTATION.md are not additional work items.

| ID | Concrete unmet work | Evidence needed to remove this row |
|---|---|---|
| PLATFORM | Obtain final-source Racket 9.2/9.3 native macOS and Windows verification. | Native builds/tests/package/docs run successfully. GitHub run 34272422677 terminates with startup_failure and zero jobs; startup cause is not established. |

Final Linux checks passed on Racket 9.2 (6,264 native tests) and 9.3 (6,268),
including 1,301 schema core cases, 86 regex cases and Scribble on each. Installed
package checks, qualified conformance/interoperability, source archive comparison,
and the original-plan evidence map are recorded in IMPLEMENTATION.md and
`test-artifacts/release-acceptance-20260908`. Only the external native-platform gate
above remains. Optional format assertions remain outside the approved
annotation-default requirement; regex support follows the tested compatibility
profile. The ordinary build identity is application-declared, as explicitly chosen.
