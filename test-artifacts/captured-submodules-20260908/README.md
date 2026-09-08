# Captured application submodules, 2026-09-08

The public captured loader rejected a fresh application's nested helper submodule
as uncaptured. A two-case regression reproduced that rejection and the missing
observation of a source parent's nested module. Both failed before the fix.

Source evaluation can deliver a compiled parent containing pre/post submodule
objects without separate evaluator calls. Compiled-file loading behaves
differently: the trace shows the parent file as current-module-declare-name while
the compiled object's name is (observed early) or (observed late). The old observer
overwrote the parent entry and left the child absent. The private module-code-tree
helper now assigns the compiled suffix to the resolved file/symbol identity and
records actual nested compiled objects in both observation and capture.

An initial fix also traversed all unused nested imports, wrongly treating a
configure-runtime dependency as loaded application code. The corrected traversal
starts from evaluated roots and their references. Retaining a nested compiled
object does not assume all its imports have been loaded.

The five final regression cases cover source/compiled application imports,
pre/post/nested modules, preserving the parent's observation, rejecting pending
work after a nested helper edit, retaining the previously loaded implementation
despite a file edit, and running a new invocation with the changed implementation.
The durable check uses one memory store across captured program generations; it
does not claim a new process-restart test. Existing process tests are part of the
full suite. A preceding four-file focused run passed 62 checks; the final added
compiled-application regression passed with the five-case suite.

Commands: raco make and raco test on captured-submodules, executable-capture,
loader and command-bootstrap. The final Racket 9.2 focused run passed 39 checks. Full Racket 9.3 validation passed compilation, 5,890 native checks, 1,301 core
schema cases, 86 optional regex cases and Scribble. All 14 Go probes, installed dependency setup and 39 installed checks
passed. Logs retain intermediate failures and trim trailing whitespace.

This fixes captured loading and observation of submodules. Default/direct serving
still needs automatic executable provenance; the explicit runtime build identity
contract is unchanged. A fresh-namespace probe alone did not remove preloaded
runtime library dependencies. No post-loading file hash is used as evidence of
executed code, and the full SDK release remains incomplete.
