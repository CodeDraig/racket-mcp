# External manifest provider identity

`before.log` reproduces a false unchanged report when one of two same-name
resource references from distinct submodules of the same file is removed.
The corrected compiler records the resolved defining module and binding phase.
The 9.2 and 9.3 focused runs each pass 55 checks. Providers throw if instantiated; inspection
reads only their application manifest. Re-export aliases deduplicate, while
moving source positions leaves the compatibility report unchanged.

```sh
raco make tests/manifest-external-identities.rkt tests/manifest-reference-bindings.rkt tests/reference-manifest.rkt tests/manifest-diff.rkt tests/phases.rkt
raco test tests/manifest-external-identities.rkt tests/manifest-reference-bindings.rkt tests/reference-manifest.rkt tests/manifest-diff.rkt tests/phases.rkt
```

Logs have trailing whitespace trimmed. All 14 Go probes, installed dependency checks and 55 installed tests passed.
Full 9.3 compilation, 5,965 native checks, all 1,301 core schema cases, all 86
optional regex cases and Scribble passed. This closes the reproduced provider collapse;
it does not claim complete cross-module interface analysis.
