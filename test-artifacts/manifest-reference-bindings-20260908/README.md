# Lexical manifest reference verification

The original regression drew an imported same-name resource from another
submodule of the same file as a reference to the local resource. `before.log`
retains that failure. Focused logs pass 95 checks on Linux Racket 9.2 and 9.3.
Log lines have trailing whitespace trimmed; test output is otherwise retained.

Commands, after selecting the corresponding isolated Racket environment:

```sh
raco make tests/manifest-reference-bindings.rkt tests/reference-manifest.rkt tests/manifest-diagram.rkt tests/manifest-diff.rkt tests/phases.rkt tests/reference-registration.rkt tests/inferred-references.rkt
raco test tests/manifest-reference-bindings.rkt tests/reference-manifest.rkt tests/manifest-diagram.rkt tests/manifest-diff.rkt tests/phases.rkt tests/reference-registration.rkt tests/inferred-references.rkt
```

The generated-binding fixture has no resource source position. Provider and
application instantiation would throw. Other cases cover consistent ID
renumbering, retargeting, local/external transitions, and dangling local targets.
All 14 official Go probes, installed package dependency checks and 95 installed
tests passed. Full 9.3 compilation, 5,962 native checks, 1,301 core schema
cases, 86 optional regex cases and Scribble passed.
This does not establish complete cross-module interface analysis.
