# Declared ordinary build identity

User decision: permit an explicit application/runtime identity for ordinary loading;
the application owns changing it when its executable dependencies change. This is
not automatic provenance and does not seal unknown code or re-instantiate modules.

Public API: mcp/build exports current-build-identity and call-with-build-identity;
make-workflow, make-runtime and serve-interface accept #:build-id, and both serving
entry points accept --build-id. Existing captured loading remains independent.
Runtime scope covers native task workers/recovery, parent rendering and upstream
MRTR/task bindings. Task input checks executable compatibility before persistence.

Evidence (terminal before this record):
- targeted-rebuilt-9.2.log: raco make then raco test of declared-build,
  declared-build-cli, tasks, executable-build and loader: 63 passed.
- installed-9.2.log and installed-9.3.log: raco setup --no-docs --check-pkg-deps
  --pkgs racket-mcp, then declared-build, declared-build-cli and cli-artifacts
  against the installed distribution with no PLTCOLLECTS override: 22 passed each.
- docs.log: raco scribble +m --htmls, terminal zero.
- go.log: scripts/check-interop.sh, all 14 official Go probes pass, terminal zero.
- ../declared-core-20260908 and ../declared-tasks-20260908: final-source refresh;
  same qualified results as conformance-closure-20260908. Tasks uses --build-id.
- source-sha256.txt records the exact SDK, test, example and fixture source.

Eight new cases cover factories, explicit constructor/scope identity, mutable input
copying, conflicting IDs, macro retention, runtime late binding, plain parent
rendering, upstream continuation/task ownership bindings, native task input/recovery,
and fresh source/compiled direct process launches. The latter count exactly one
application initialization per process and verify unchanged restart and changed-ID
rejection without completing the old handler.

The first focused probe used #:version instead of the resource grammar's #:workflow
and was corrected before the successful focused run. targeted-9.2.log retains a
stale compiled test linklet failure; recompiling dependencies resolved it. The first
Tasks server startup similarly preceded fixture recompilation; its log is retained
in that artifact directory. Neither is reported as a passing execution.

Full Linux 9.2/9.3 source checks are running; their logs will be recorded terminally
before release verification closes. The preceding full 9.2 run completed with 6,256
native checks, 1,301 schema cases, 86 regex cases and Scribble.
