# Manifest provider phases

One provider defines resource `document` at phases zero and one. A language
module imports both into its runtime phase, using an ordinary import and a
negative phase shift. Its generated manifest retains distinct defining phases
for the otherwise same provider/submodule identity. Removing either reference
requires review in manifest-diff. Ordinary application and provider instantiation
throw; reading the generated manifest succeeds. Compilation still executes
trusted Racket phase code as documented.

Compilation and 56 focused checks passed on Linux Racket 9.2 and 9.3:

```
raco make tests/manifest-provider-phases.rkt tests/manifest-external-identities.rkt tests/manifest-reference-bindings.rkt tests/manifest-diff.rkt tests/reference-manifest.rkt
raco test tests/manifest-provider-phases.rkt tests/manifest-external-identities.rkt tests/manifest-reference-bindings.rkt tests/manifest-diff.rkt tests/reference-manifest.rkt
```

The same 56 checks passed from the installed 9.3 source distribution. No compiler/runtime code changed, and the full
protocol/crash suite is not repeated for these two new regression cases. Other
manifest and complete-release acceptance gates remain open.
