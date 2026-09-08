# Remaining release work

Mutable current state for the approved seven-milestone MCP 2026-07-28 release.
Remove a row when its completion evidence is recorded in IMPLEMENTATION.md;
replace a partial row with only its unmet portion. Do not reopen completed work
without a regression or a dependency of a remaining requirement. Historical
"remains open" statements in IMPLEMENTATION.md are not additional work items.

| ID | Concrete unmet work | Evidence needed to remove this row |
|---|---|---|
| BUILD | Integrate automatic runtime identity and successfully initialized, sealed dependency captures into default/direct language and ordinary library workflow construction. | Fresh source and compiled launches; unchanged restart accepted; changed helper/runtime rejected; failed initialization never seals; factory and data API paths agree. |
| CONFORMANCE | Finish applicable core/client/Tasks conformance using appropriate fixtures and Go interoperability; classify discrepancies and exclusions. | Final-source results per applicable scenario; Tasks header and shutdown/MRTR interpretations documented; harness gaps distinguished from SDK failures. |
| PLATFORM | Obtain final-source Racket 9.2/9.3 native macOS and Windows verification. | Native builds/tests/package/docs run successfully. Current GitHub runs terminate before jobs start; startup cause is not established. |
| RELEASE | Run final-source Linux 9.2/9.3, installed-package dependency checks, Scribble and reproducible distribution; reconcile this table against the original plan. | Terminal logs and reproducible hashes for the release source; every original acceptance item mapped to evidence or an explicit external blocker. |

Latest baseline: the authored-example compiler changes passed 6,238 native tests,
1,301 schema core cases, 86 regex cases and Scribble on Linux Racket 9.3. Twenty
subsequently integrated language/durability cases passed on both 9.2 and 9.3. This does not reopen
previously demonstrated behavior. Optional format assertions remain outside the
approved annotation-default requirement; regex support is assessed against the
promised tested compatibility profile, not an invented full-JavaScript mandate.
