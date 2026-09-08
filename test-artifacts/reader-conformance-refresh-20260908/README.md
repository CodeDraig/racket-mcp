# Reader conformance refresh

Source: ed75ea847a1d97b4a834af82bf4d77cca0ff8e2a. Harness exited 1.
Required checks: 110 success, four failure, three warning, one info.
The four failures use excluded roots/sampling fixtures. Two warnings lack actual
list-mutation diagnostic hooks. The remaining warning is the recorded MRTR
input-responses-without-continuation interpretation.

The requirements runner also ran Tasks scenarios against the core fixture, which
lacks their diagnostic tools. Those failures do not establish Tasks compliance or
SDK defects. Use the dedicated Tasks fixture for that gate. The harness itself
skips Tasks notification checks pending its subscription-channel rewrite.

run.py is the exact orchestration script; commands.json records resolved arguments.
harness-inputs.json compares the executed source/requirements/package inputs with
the pinned vendor tree. Raw failed results are retained. No upstream code changed.
