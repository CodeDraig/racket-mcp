# Remaining release work

Mutable current state for the approved seven-milestone MCP 2026-07-28 release.
Remove a row when its completion evidence or an approved scope change is recorded
in IMPLEMENTATION.md;
replace a partial row with only its unmet portion. Do not reopen completed work
without a regression or a dependency of a remaining requirement. Historical
"remains open" statements in IMPLEMENTATION.md are not additional work items.

No remaining requirements in the approved release scope.

On 2026-09-08, the user removed native macOS/Windows testing from the plan
because no immediate verification route is available. This removes the PLATFORM
requirement; it does not establish support on either platform. Linux Racket
9.2/9.3 is the verified release platform. Native macOS/Windows remain unverified.

Final Linux checks passed on Racket 9.2 (6,264 native tests) and 9.3 (6,268),
including 1,301 schema core cases, 86 regex cases and Scribble on each. Installed
package checks, qualified conformance/interoperability, source archive comparison,
and the original-plan evidence map are recorded in IMPLEMENTATION.md and
`test-artifacts/release-acceptance-20260908`. The historical platform gate in
that evidence map is superseded by the scope change above. Optional format assertions remain outside the approved
annotation-default requirement; regex support follows the tested compatibility
profile. The ordinary build identity is application-declared, as explicitly chosen.

Completion of this scope is not an unqualified MCP conformance or SDK-tier claim.
The recorded conformance exclusions and disagreements remain unchanged.
