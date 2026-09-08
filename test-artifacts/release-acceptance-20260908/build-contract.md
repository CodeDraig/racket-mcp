# Accepted ordinary durable-loading contract

On 2026-09-08 the user selected: "Allow an explicit application/runtime build
identity for ordinary loading, with the application responsible for updating it."
This replaces the outstanding request for automatic default-path provenance.

The retained compiled bootstrap probe leaves 643 ordinary dependencies and 22
predefined modules unknown. Observation cannot identify code loaded before it
began. Ordinary loading therefore accepts a declared identity, without pretending
it observed or sealed those dependencies and without re-instantiating applications.

The separate captured loader remains available: it observes application code in a
fresh namespace, shares actual SDK instances, rejects unknown application modules,
and seals only after successful initialization. Its explicit runtime-baseline
identity remains caller-supplied. Linux /proc/self/exe identifies the running image,
not all runtime shared libraries or installation files.

Implementation and evidence: ../declared-build-20260908. The application must update
its declared ID for changes to executable dependencies; reusing a stale ID violates
the contract. No automatic inference of compatibility or migration is promised.
