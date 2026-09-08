# Declared module code capture

The new private component freezes registry-scoped observation records and
retained producer identities without reading source files, instantiating modules
or obtaining user exports. It includes observed dynamic declarations conservatively
and leaves unknown dependencies explicit. The snapshot interoperates with the
existing explicit sealer and its execution guard.

Focused compilation and 59 checks passed on both Racket 9.2 and 9.3. Cases cover distinct
registries, source replacement after loading, immutable snapshots, later dynamic
declarations, refusing incomplete sealing, retained execution and a throwing
uninstantiated module. A #lang mcp module also captures its own declaration during
initialization, exercising the registry lock at the intended hook boundary.

```sh
raco make tests/declared-code-capture.rkt tests/module-observation.rkt tests/executable-capture.rkt tests/captured-dynamic-imports.rkt tests/retained-capture.rkt
raco test tests/declared-code-capture.rkt tests/module-observation.rkt tests/executable-capture.rkt tests/captured-dynamic-imports.rkt tests/retained-capture.rkt
```

Logs have trailing whitespace trimmed. Installed-package dependency checks and all 59 focused cases also passed.
The broad protocol/crash suite was not repeated: default loading is unchanged
and the new capture component is not yet called by production workflows. This component is not yet wired into default workflow construction;
runtime baseline identities and the complete release remain open. The capture
is a module-code snapshot, not proof about arbitrary ambient closures.
