# Direct-launch capture experiments

These are isolated Linux Racket 9.2 probes at SDK commit 6184c15. They do not
install a new language entry or seal production workflow builds. The full Racket
9.3 suite ran against unchanged SDK source while these separate processes ran.

Each peer answers the existing capture-baseline tool. The response contains
unobserved names, predefined names and the ordinary unobserved subset. Raw
responses and summary.json retain those counts. The initial direct peer used the
already compiled dev/command-observation-server.rkt. A new temporary filename with
no compiled counterpart is the source-launch control.

| Launch | Ordinary dependencies without identities |
| --- | ---: |
| Existing compiled direct launch | 643 |
| Existing cold command launcher | 0 |
| Plain configure-runtime observer, compiled application | 83 |
| Kernel/scoped configure-runtime initialization, compiled application | 0 |
| Existing fresh-source direct launch | 86 |
| Kernel/scoped runtime initialization, fresh source, no earlier seed | 643 |
| Same experiment with all compiled files disabled (-c) | 629 |
| Runtime initialization preserving earlier observation seed, fresh source | 87 |

All reports include 22 unobserved predefined modules in addition to the ordinary
counts. The seeded fresh-source experiment's extra ordinary module, relative to
the fresh-source baseline, is mcp/private/kernel-observation.rkt itself. Each of
the fresh-source, seeded and -c experiments recorded exactly one application
initialization in its independent count file.

The initial -c probe exceeded its experimental 30-second request deadline. It was
terminal and cleaned up by the scenario runner. A separate 120-second run
completed; no SDK timeout policy was changed. The stored source probe uses that
final 120-second deadline, while the shorter failure is retained separately.

The Racket reference, startup.scrbl section configure-runtime, says this submodule
is dynamically required before the main module is instantiated. These results
confirm its usefulness for compiled entry, but falsify using it alone as the
source-launch solution. Source expansion can load dependencies before this hook.
Earlier observations must also survive entry into the runtime capture scope.
No disk hashes were substituted for already loaded code identities.

Inputs remain temporary probes, not public SDK examples. To reproduce, copy the
mcp-*.rkt inputs from this directory to /tmp, preserving filenames. Use the
repository as cwd, source scripts/racket-env.sh, and set
PLTCOMPILEDROOTS=$PWD/.cache/ci/compiled-9.2-effect. For the compiled experiments,
run raco make on the matching temporary server before running its probe script.
For fresh-source controls use a new filename and do not compile it first. Empty
the corresponding initialization count file before each counter experiment.
The original default probe uses the repository's dev fixture and mcp/command.rkt.

Next integration work must cover early reader/compiler bootstrap observation,
preservation of prior registry-scoped evidence, compiled runtime configuration,
and complete sealing with a justified predefined-runtime identity. This probe
proves none of those release gates complete and does not alter SDK behavior.
