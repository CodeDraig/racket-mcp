# Public extension binding phase matrix

A generated provider exports schema, operation, resource and prompt declarations;
a forwarding module renames and re-exports each. Consumers at phases 0, 1 and 2
query those bindings through mcp/extension. Authored expectations check original
resource/prompt identity and argument names, domain kinds, ordinary host names,
local shadowing and wrong-kind errors attached to the renamed caller identifier.
Provider handlers raise if invoked, so metadata queries cannot pass by calling
application handlers. No private compiler modules are imported by this matrix.

Compilation and 41 checks passed on Linux Racket 9.2 and 9.3:

```
raco make tests/extension-phase-matrix.rkt tests/extension-bindings.rkt tests/workflow-extension-bindings.rkt tests/workflow-effect-bindings.rkt tests/phase-exports.rkt
raco test tests/extension-phase-matrix.rkt tests/extension-bindings.rkt tests/workflow-extension-bindings.rkt tests/workflow-effect-bindings.rkt tests/phase-exports.rkt
```

The same 41 checks passed from the installed 9.3 source distribution. Runtime and compiler code are unchanged
from d906531; the broad protocol/crash suite is not repeated for this test-only
addition. This is finite phase coverage, not completion of all compiler gates.
