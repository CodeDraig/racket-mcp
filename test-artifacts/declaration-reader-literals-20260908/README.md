# Invalid schema reader literals

All 44 negative cases reproduced successful expansion for malformed schema
literals: string and byte regexps, boxes, and prefab structures in eleven schema
positions. The fixed compiler diagnoses each literal at its original source and
line without evaluating host expressions. Existing shadowed-quote and dynamic
schema tests remain part of the focused suite.

Commands (using the version-specific project environment):

```
raco make tests/declaration-reader-literals.rkt tests/declaration-schemas.rkt tests/domain-bindings.rkt tests/compiler.rkt
raco test tests/declaration-reader-literals.rkt tests/declaration-schemas.rkt tests/domain-bindings.rkt tests/compiler.rkt
```

Compilation and 118 focused checks passed on Linux Racket 9.2 and 9.3.
Installed package dependency checks and the same 118 tests passed on 9.3.
All 14 official Go probes passed. Full 9.3 verification passed compilation,
6,044 native checks, all 1,301 core schema cases, all 86 optional regex cases, and
the final Scribble manual build.

The manual also now has an indexed mcp/interaction module and run-interaction
signature, callback arities, return representation and polling policy. Its
separate Scribble build passed; this documentation change does not alter runtime
behavior.

The stdio reference now indexes the client constructor, request-handle predicate,
ID and notification accessors, cancellation and close functions. The descriptions
were checked against the stdio and HTTP handle implementations; the additional
Scribble build passed. The remaining request/server API reference work is not
claimed complete by this entry.

Trailing whitespace was trimmed from the installed setup log for Git checks.

Two consecutive `python3 scripts/package.py` runs produced identical ZIP hashes;
`cmp` passed and SHA256SUMS records the digest. Native macOS/Windows verification
and the remaining full-release gates are unchanged.
