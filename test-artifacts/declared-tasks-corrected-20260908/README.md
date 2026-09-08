# Tasks refresh after task guard correction

Executed the unmodified pinned Tasks harness against final-source-sha256.txt in
../declared-build-20260908, with --build-id conformance-declared/1 on the server.
43 SUCCESS, one FAILURE and one SKIPPED: the same taskId/header disagreement and
unfinished harness notification rewrite documented in conformance-closure-20260908.
The correction preserves ordinary adapter mismatch failure in the task worker;
only a changed declared identity rejects input before persistence.

scenario-exits.json distinguishes harness failures from the runner exit. run.py
verifies pinned source/requirements/package hashes and records exact commands.
No protocol or harness expectation was weakened to obtain this result.
