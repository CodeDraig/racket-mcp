# Automatic executable provenance probes, 2026-09-08

These are unsuccessful design probes, not an implemented automatic loader. They
were run while completing the captured-submodule fix after commit 6c50cf2.

The fresh-namespace probes used Racket 9.3 and the observer before that fix.
make-base-empty-namespace retained already-loaded library dependencies. A fully
empty namespace needed predefined runtime modules attached to instantiate the
application; omitting them produced unknown #%paramz / #%unsafe errors. Attaching
the observed predefined modules and clearing the module cache still left ordinary
runtime dependencies without observed code. Missing nested submodules in these
logs motivated the separate implemented fix; the other missing dependencies do
not become measured merely because the namespace is new. These scripts reference
the task's original workspace and are retained as experiment inputs.

A separate Racket 9.2 probe installed an evaluator hook in a configure-runtime
submodule and ran the application first from source, then after raco make. Both
runs executed CONFIGURE, the helper call, and MAIN. Only the compiled run observed
the helper's compiled code after configuration. Source compilation had already
loaded that helper before the runtime hook. Reproduce by placing the retained
configure-runtime-application.rkt and configure-runtime-helper.rkt together as
application.rkt and helper.rkt, then running racket application.rkt, raco make
application.rkt, and racket application.rkt. The hook reports evaluator calls; it
does not hash files or infer execution identity from their current contents.

Therefore neither a fresh namespace alone nor configure-runtime alone establishes
the planned automatic default/direct executable compatibility guarantee. The
explicit captured loader remains available. The full SDK goal is still active;
these probes identify constraints on the unfinished loading path rather than
declaring that path impossible or accepting a reduced release contract.
