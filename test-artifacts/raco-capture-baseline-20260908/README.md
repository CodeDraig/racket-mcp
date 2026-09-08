# Raco executable capture baseline

The extended command-observation fixture freezes the actual observed graph and
reports missing identities separately from predefined runtime modules. Direct
file and library command entries passed on Linux Racket 9.2 and 9.3. The 9.3
report contains 22 predefined modules and no unidentified ordinary dependencies.

Adding the real `raco mcp` invocation reproduced missing ordinary Racket modules
loaded by raco before the SDK observer starts. The three-entry baseline test
failed for that invocation.
A fresh-registry experiment attaching only predefined primitive modules did not
restore full observation; its runtime change was removed. Its log is retained.
The development fixture and regression are retained for the correction.

Commands: version-scoped `raco make dev/command-observation-server.rkt
 tests/command-observation.rkt`; `raco test tests/command-observation.rkt`.
The report used call-with-scenario-process against racket -l mcp/command.
No default workflow loading or runtime baseline policy has been changed.

## Correction

The raco registration now starts the kernel entry in a fresh Racket process from
the same installation. Literal arguments, standard streams and status are
forwarded. A custodian terminates the child on launcher interruption. Forced,
uncatchable parent-only termination requires supervisor process-tree cleanup;
this is documented and has not been claimed as covered by the break test.

Five new launcher cases include a real listener acquired by a child, followed by
launcher interruption and verification that the listener closes. The loader
restart regression now executes both direct CLI and raco entries. Linux 9.3
passed 59 focused checks and the manual build. The first 9.2 run failed because
of an outdated compiled greeter fixture; its precise linklet diagnostic is saved.
Final checks explicitly compile that fixture. Final results are recorded below.

Commands: raco make for the five focused test files and their dynamic fixtures;
raco test tests/raco-launcher.rkt tests/command-observation.rkt
 tests/command-bootstrap.rkt tests/command-process.rkt tests/loader-cli-restart.rkt;
raco setup --no-docs --check-pkg-deps --pkgs racket-mcp; raco scribble +m --htmls;
python3 scripts/package.py. Package checks use an isolated package home and no
PLTCOLLECTS; 9.2 uses an isolated compiled root. Logs have trailing whitespace
removed only. Full SDK and native-platform gates remain open.

Final verification: all 59 focused checks passed on Linux Racket 9.2 and 9.3
and from the installed 9.3 distribution. Installed dependency checks and the
Scribble build passed. The distribution was built twice and byte-compared; its
ZIP digest is recorded in distribution-SHA256SUMS. The broad native suite was
not repeated for this launcher change; the earlier 6,112 count is historical.
