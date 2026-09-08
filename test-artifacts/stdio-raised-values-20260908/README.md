# Stdio arbitrary raised-value lifecycle

The baseline leaves a request unresolved after a custom reader raises a symbol.
A custom close callback raising a symbol also skips remaining cleanup. Both
failures are retained in before.log. An earlier probe fixture incorrectly paired
an input-port read delegate with a false peek delegate; that fixture was corrected
before the retained baseline run.

The fix handles non-break failures, preserves existing exception identities,
and wraps other values in exn:fail:stdio with an unchanged cause field. Cleanup
attempts both owned ports and worker shutdown despite callback failures, with
asynchronous breaks deferred across the close operation. Borrowed ports remain
open. The close policy continues to suppress cleanup callback failures.

The focused six-file suite passes 130 checks on Linux Racket 9.2 and 9.3:

```sh
raco make tests/stdio-raised-values.rkt tests/stdio-lifecycle.rkt tests/stdio-cancellation.rkt tests/stdio-timeouts.rkt tests/stdio-overflow.rkt tests/stdio-output-failure.rkt
raco test tests/stdio-raised-values.rkt tests/stdio-lifecycle.rkt tests/stdio-cancellation.rkt tests/stdio-timeouts.rkt tests/stdio-overflow.rkt tests/stdio-output-failure.rkt
```

The writer regression was then strengthened to exercise client-call. All four
raised-value cases passed again on each version (sync logs). Logs have trailing
whitespace trimmed. The Scribble build also passed in the isolated worktree.
Installed-package dependency checks, 130 installed tests and all 14 official Go
probes passed after integration. Full 9.3 compilation, 5,969 native checks, all
1,301 core schema cases, all 86 optional regex cases and Scribble passed.
The tested fix was applied to the main worktree after the manifest change
completed verification.
