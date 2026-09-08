# Interface reference acceptance closure

This audit closes REFERENCES, not the separate general LANGUAGE or durable
embedding gates. Existing tests were inspected; no additional reference tests
were added to repeat established behavior.

| Approved reference behavior | Evidence |
|---|---|
| Resource applications are checked references, not I/O; macro/data parity | tests/resource-reference-contract.rkt |
| Renamed imports, forward declarations, macro-generated handler references, shadowing/quotes | tests/inferred-references.rkt, tests/reference-manifest.rkt |
| Checkpoint/input/effect/branch/completion references and workflow prompt/resource bodies | tests/workflow-references.rkt |
| Explicit dynamic reference maps, removal, identity rather than name, ambiguous mounts | tests/interface-references.rkt |
| Removed/re-exported resources, additional supplying mounts, colliding hygienic identities | tests/composed-reference-checks.rkt |
| Fragment imports, literal views, URI/name mapping, dynamic mounts recorded as unknown | tests/manifest-composition.rkt |
| Manifest local/external identity, generated forms without source positions | tests/manifest-reference-bindings.rkt |
| Completion target/argument checking, runtime raw descriptor validation | tests/completion-references.rkt |
| Renamed/nested prompt completion, removal and retained authorization scopes | tests/prompt-completion-composition.rkt |
| Extension-generated resources/search/completion survive namespaces and URI remaps | tests/collection-extension.rkt, tests/extension-bindings.rkt |
| Visiting-thread binding registration survives use by other threads | tests/reference-registration.rkt |

All named tests passed in the full ed75ea8 Linux 9.3 run, retained in
../reader-full-refresh-20260908. Their files are unchanged since that source.
The compiler checks lexical declaration references and explicit interface maps;
arbitrary host computation remains host computation. Dynamically produced links
and embeddings still reject absent/ambiguous resources at resolution, before
reading either resource. The original plan permits dynamic information to remain
unknown statically and requires runtime checks; no whole-program Racket analysis
has been substituted for that requirement.
