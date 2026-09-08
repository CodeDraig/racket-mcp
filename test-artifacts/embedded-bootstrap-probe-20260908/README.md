# Embedded runtime observation probe

Temporary hypothesis: embedding the kernel observer in an application runtime
configuration submodule would remove the observer's separate unobserved module
and capture default compiled startup. Source launch leaves zero ordinary and 22
predefined unobserved dependencies. After raco make, the same launch leaves 643
ordinary and 22 predefined dependencies unobserved. Both commands terminated
successfully; these counts are failure evidence for the compiled-path hypothesis,
not a passing implementation check. No SDK source changed.

prepare.py generated the temporary application and driver. The command sequence
used scripts/racket-env.sh, PLTCOMPILEDROOTS=.cache/ci/compiled-9.2-effect,
`racket probe.rkt`, then `raco make application.rkt; racket probe.rkt`.
Copies retain their original temporary paths; prepare.py creates a new directory
and driver when rerun. JSONL output records the original entry arguments.

The compiled module has the kernel identity-info provider with no delegated
runtime provider and contains the configure-runtime submodule. The root and its
ordinary dependencies are declared before the runtime hook can capture their
code. Embedding the observer therefore does not establish default compiled build
sealing. BUILD remains; do not repeat this approach without a new earlier capture
boundary or retained dependency-identity mechanism.
