# Final-source conformance refresh

Runs the exact pinned harness against the declared-build SDK source recorded in
../declared-build-20260908/source-sha256.txt. summary.json retains all statuses.
Core: 144 successes, four excluded roots/sampling failures, one MRTR interpretation
warning and one info, excluding Tasks run against the core fixture (15/27/1).
Dedicated Tasks: 43 successes, one taskId/header disagreement and one harness
notification skip; the server declares --build-id conformance-declared/1.
Qualifications and source rationale are unchanged from conformance-closure-20260908.
No harness or protocol expectation was patched. Client/OAuth source is unchanged
by this integration and its preceding qualified evidence remains applicable.

run.py records commands and verifies harness input hashes. The runner exits zero
after saving scenario results; harness exit status is separately retained and must
not be confused with the runner's status. A failed initial Tasks fixture startup
from stale compiled code is retained in server-before-rebuild.log where present;
raco make resolved it before this completed refresh.
