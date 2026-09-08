# Prompt completion composition

The baseline reproduced three failures: a completion outside a renamed prompt
view failed at construction, the static manifest retained its old target name,
and excluding an imported target did not fail expansion. Runtime views now keep
a private prompt declaration identity while preserving the public five-argument
constructor. Completion construction resolves that identity through nested views
and raw interfaces, rejects ambiguous/absent/duplicate targets, and preserves
the published prompt's scope requirements.

Prompt binding origins and local IDs now flow through independent manifests.
Completion prompt-reference values survive prefixing and provider rebasing;
exclusions survive re-exports. Diffs normalize incidental compiler IDs and binding
names. Diagrams show resolved prompt targets or explicit unresolved nodes.

A further probe found a false duplicate when a renamed imported prompt and an
unrelated local prompt shared an original name. Static checking now uses lexical
references instead of falling back to the other declaration's name. The positive
regression instantiates both routes and checks their distinct handler outcomes.

Eleven authored cases cover these behaviors, authorization before handler
execution, dynamic restoration, independent inspection, and raw construction.
Initial 471-check runs on both Racket versions exposed an older diff fixture that
discarded the prompt while retaining its newly explicit local reference. The
fixture now retains the target; dangling-reference validation remains intact.
After correction, 63 prompt/completion/diagram checks passed on Linux 9.3.
Final source passed 472 focused checks on Linux Racket 9.2 and 9.3, and
472 checks across 25 separately executed files in the installed 9.3 package.
Installed dependency setup and all 14 official Go probes passed. The full 9.3
run passed 6,112 native tests, 1,301 core schema cases, 86 optional regex cases,
and the Scribble manual build. The distribution was built twice and compared
byte for byte; distribution-SHA256SUMS records its digest.

```sh
raco make mcp/*.rkt tests/*.rkt
raco test tests/prompt-completion-composition.rkt tests/completion-references.rkt tests/manifest-diagram.rkt
sh scripts/check.sh
sh scripts/check-interop.sh
raco setup --check-pkg-deps --pkgs racket-mcp
python3 scripts/package.py
```

Source runs use scripts/racket-env.sh and version-specific package homes. Racket
9.2 uses an isolated compiled root; dynamic manifest fixtures are explicitly made.
Installed verification unsets PLTCOLLECTS and uses the copied source package.
The full SDK, conformance, and native macOS/Windows release gates remain open.

Stored installed-package output has trailing whitespace removed; test output
and counts are otherwise unchanged.
